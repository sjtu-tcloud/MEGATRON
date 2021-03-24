#!/usr/bin/python3

from flask import Flask
from flask import request
from werkzeug.serving import make_server
import logging
from fabric import Connection
from fabric import ThreadingGroup
import threading
import time
import signal
import sys
import os

log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

os.system('/home/img/optimus-host-module/reload.sh')
os.system('sudo /usr/local/bin/fpgaconf -b 0x5e /home/img/bitstream/mux8_membench.gbs')
os.system('/home/img/optimus-host-module/reload.sh')

print("reconfiguration is done")

ip_list = []
app = Flask(__name__)

@app.route('/ping')
def ping():
    if (request.remote_addr in ip_list):
        return "existed"
    ip_list.append(request.remote_addr)
    return "pong"

@app.route('/report', methods=['POST'])
def report():
    s = request.form.get('s')
    print("received from [", request.remote_addr, "]:", s)
    return ""

class ServerThread(threading.Thread):
    def __init__(self, app):
        threading.Thread.__init__(self)
        self.srv = make_server('0.0.0.0', 5000, app)
        self.ctx = app.app_context()
        self.ctx.push()

    def run(self):
        print('starting server')
        self.srv.serve_forever()

    def shutdown(self):
        self.srv.shutdown()

def start_server():
    global server
    server = ServerThread(app)
    server.start()
    print('server started')

def stop_server():
    global server
    server.shutdown()

start_server()

def sigint_handler(sig, frame):
    stop_server()
    os.system('sudo pkill -9 qemu > /dev/null')
    sys.exit()

signal.signal(signal.SIGINT, sigint_handler)

print("Booting VM 0...")
os.system('bash /home/img/script/boot-vm.sh 0 > /dev/null 2> /dev/null &')
print("Booting VM 1...")
os.system('bash /home/img/script/boot-vm.sh 1 > /dev/null 2> /dev/null &')

while True:
    time.sleep(1)
    if (len(ip_list) == 0):
        print("No received IP address, wait for booting...")
    if (len(ip_list) == 1):
        print("Received IP addresses:", ip_list, "wait for the other to boot up...")
    if (len(ip_list) == 2):
        print("Received IP addresses:", ip_list, "start running benchmark...")
        break

login_list = []
for ip in ip_list:
    login_list.append("root@"+ip)


cmd_tmpl = '''curl -F "s=`/root/optimus-intel-fpga-bbb/samples/tutorial/vai_membench/sw/cci_membench_vai ${SIZE} 10000000 0 RD_VA WR_VA RDLINE_I WRLINE_I RAND RDCL1 2>/dev/null | grep "RD thr" | awk '{print $3 $4}'`" http://fpga-skx:5000/report'''

print("\n******************************** 1 VM: MemBench with 4096-page working set **************************************")
result = Connection(login_list[0], connect_kwargs={"password": "a"}).run(cmd_tmpl.replace("${SIZE}", "4096"), hide=True)

print("\n*************************** 2 VMs: MemBench with 2048-page working set for each *********************************")
result = ThreadingGroup(*login_list, connect_kwargs={"password": "a"}).run(cmd_tmpl.replace("${SIZE}", "2048"), hide=True)

input('\nPress ENTER to exit...')
stop_server()
os.system('sudo pkill -9 qemu > /dev/null')
