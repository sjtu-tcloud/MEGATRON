//
// Copyright (c) 2019, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.


`include "mpf_vtp.vh"


//
// Page translation service that uses software to translate virtual to
// physical addresses.
//

module mpf_svc_vtp_pt_sw
  #(
    parameter DEBUG_MESSAGES = 0
    )
   (
    input  logic clk,
    input  logic reset,

    // Primary interface
    mpf_vtp_pt_walk_if.server pt_walk,

    // FIM interface for host I/O
    mpf_vtp_pt_host_if.pt_walk pt_fim,

    // CSRs
    mpf_vtp_csrs_if.vtp csrs,

    // Events
    mpf_vtp_csrs_if.vtp_events_pt_walk events
    );

    // Page translation request buffer's physical address.
    cci_mpf_if_pkg::t_cci_clAddr pt_req_buf_pa;
    logic initialized;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            initialized <= 1'b0;
        end
        else
        begin
            if (csrs.vtp_ctrl.page_translation_buf_paddr_valid)
            begin
                initialized <= 1'b1;
                pt_req_buf_pa <= csrs.vtp_ctrl.page_translation_buf_paddr;
            end
        end
    end


    // ====================================================================
    //
    //   Handle incoming requests.
    //
    // ====================================================================

    //
    // Incoming requests first go in a register. The protocol can accept
    // a new request at most every other cycle, which is plenty for a
    // service that will send its requests to software.
    //
    logic req_valid;
    logic send_req;
    t_tlb_4kb_va_page_idx req_va; //36 bits
    t_mpf_vtp_pt_walk_meta req_meta;
    logic req_isSpeculative;
    t_mpf_vtp_req_tag req_tag;

    assign pt_walk.reqRdy = ~req_valid;

    always_ff @(posedge clk)
    begin
        if (pt_walk.reqEn)
        begin
            req_valid <= 1'b1;
            req_va <= pt_walk.reqVA;
            req_meta <= pt_walk.reqMeta;
            req_isSpeculative <= pt_walk.reqIsSpeculative;
            req_tag <= pt_walk.reqTag;
        end

        if (reset || send_req)
        begin
            req_valid <= 1'b0;
        end
    end


    //
    // Requests will be processed FIFO. Store request metadata in a FIFO
    // to avoid sending it to the host. This FIFO also serves as a rate
    // limiter on the use of the request ring buffer. It ensures that
    // few enough requests are in flight to avoid overwriting requests
    // in the ring buffer.
    //

    logic req_not_full;
    logic req_not_empty;

    logic rsp_en;
    t_tlb_4kb_va_page_idx rsp_va;
    t_mpf_vtp_pt_walk_meta rsp_meta;
    logic rsp_isSpeculative;
    t_mpf_vtp_req_tag rsp_tag;

    assign send_req = req_valid && req_not_full &&
                      initialized && pt_fim.writeRdy;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_tlb_4kb_va_page_idx) +
                     $bits(t_mpf_vtp_pt_walk_meta) +
                     1 +
                     $bits(t_mpf_vtp_req_tag)),
        .N_ENTRIES(8),
        .REGISTER_OUTPUT(1)
        )
       req_fifo
        (
         .clk,
         .reset,

         .enq_data({ req_va, req_meta, req_isSpeculative, req_tag }),
         .enq_en(send_req),
         .notFull(req_not_full),
         .almostFull(),

         .first({ rsp_va, rsp_meta, rsp_isSpeculative, rsp_tag }),
         .deq_en(rsp_en),
         .notEmpty(req_not_empty)
         );


    // ====================================================================
    //
    //  Send requests to the host.
    //
    // ====================================================================

    //
    // Requests are written to the first 64 bit word in a single 4KB page
    // ring buffer. The req_fifo above limits the number of outstanding
    // requests to avoid overwriting active requests.
    //

    // Line index in the request ring buffer
    logic [5:0] req_ring_idx;

    assign pt_fim.readEn = 1'b0;

    always_ff @(posedge clk)
    begin
        pt_fim.writeEn <= send_req;

        // The ring buffer address must be page-aligned, so just replace
        // the low bits with the ring entry index.
        pt_fim.writeAddr <= pt_req_buf_pa;
        pt_fim.writeAddr[5:0] <= req_ring_idx;

        // Send the request as a standard virtual address. The low
        // bit is forced to one in case a NULL pointer is sent.
        // Of course NULL will result in an error, but this way it
        // will be detected.
        //
        // Bit 1 indicates whether the request is speculative.
        pt_fim.writeData <=
            { req_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0), 4'b0, req_isSpeculative, 1'b1 };

        if (send_req)
        begin
            req_ring_idx <= req_ring_idx + 6'b1;
        end

        // Clear the counter on reset and when the request buffer address
        // changes.
        if (reset || csrs.vtp_ctrl.page_translation_buf_paddr_valid)
        begin
            req_ring_idx <= 6'b0;
        end
    end


    // ====================================================================
    //
    //  Forward responses from the host.
    //
    // ====================================================================

    logic rsp_valid;
    t_tlb_4kb_pa_page_idx rsp_pa;
    logic rsp_not_present;
    logic rsp_is_big_page;

    assign rsp_en = rsp_valid && req_not_empty;

    always_ff @(posedge clk)
    begin
        //rsp_valid <= csrs.vtp_ctrl.page_translation_rsp_valid;
        //rsp_pa <= vtp4kbPageIdxFromPA(csrs.vtp_ctrl.page_translation_rsp);

        // Encode failed translation in bit 0
        //rsp_not_present <= csrs.vtp_ctrl.page_translation_rsp[0] &&
        //                   csrs.vtp_ctrl.page_translation_rsp_valid;

        // Encode page size in bit 1
        //rsp_is_big_page <= csrs.vtp_ctrl.page_translation_rsp[1];

        rsp_valid <= pt_fim.readDataEn;
        rsp_pa <= vtp4kbPageIdxFromPA(pt_fim.readData);
        rsp_not_present <= pt_fim.readDataEn && pt_fim.readData[0];
        rsp_is_big_page <= pt_fim.readData[1];
        
        if (reset)
        begin
            rsp_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk)
    begin
        pt_walk.rspEn <= rsp_en;
        pt_walk.rspVA <= rsp_va;
        pt_walk.rspPA <= rsp_pa;
        pt_walk.rspMeta <= rsp_meta;
        pt_walk.rspIsSpeculative <= rsp_isSpeculative;
        pt_walk.rspTag <= rsp_tag;
        pt_walk.rspIsBigPage <= rsp_is_big_page;
        pt_walk.rspIsCacheable <= 1'b1;
        pt_walk.rspNotPresent <= rsp_not_present && rsp_en;
    end

    // Statistics and events
    always_ff @(posedge clk)
    begin
        events.vtp_pt_walk_events.busy <= req_not_empty;
        events.vtp_pt_walk_events.failed_translation <= rsp_not_present && rsp_en;

        // The "last" request is the one currently waiting for a response at
        // the head of the request FIFO.
        if (req_not_empty)
        begin
            events.vtp_pt_walk_events.last_vaddr <= { rsp_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0) };
        end

        if (reset)
        begin
            events.vtp_pt_walk_events.last_vaddr <= 0;
        end
    end


    // ====================================================================
    //
    //  Debugging
    //
    // ====================================================================

    always_ff @(posedge clk)
    begin
        if (! reset && DEBUG_MESSAGES)
        begin
            // synthesis translate_off
            if (send_req)
            begin
                $display("VTP PT WALK %0t: New REQ translate VA 0x%x (line 0x%x), tag (%0d, %0d)",
                         $time,
                         { req_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0), 6'b0 },
                         { req_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0) },
                         req_meta, req_tag);
            end

            if (rsp_en && rsp_not_present)
            begin
                $display("VTP PT WALK %0t: Completed RESP FAILED %sTRANSLATION, VA 0x%x (line 0x%x), tag (%0d, %0d)",
                         $time,
                         (rsp_isSpeculative ? "speculative " : ""),
                         { rsp_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0), 6'b0 },
                         { rsp_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0) },
                         rsp_meta, rsp_tag);
            end
            else if (rsp_en)
            begin
                $display("VTP PT WALK %0t: Completed RESP PA 0x%x (line 0x%x), VA 0x%x (line 0x%x), tag (%0d, %0d), %0s",
                         $time,
                         { rsp_pa, VTP_PT_4KB_PAGE_OFFSET_BITS'(0), 6'b0 },
                         { rsp_pa, VTP_PT_4KB_PAGE_OFFSET_BITS'(0) },
                         { rsp_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0), 6'b0 },
                         { rsp_va, VTP_PT_4KB_PAGE_OFFSET_BITS'(0) },
                         rsp_meta, rsp_tag,
                         (rsp_is_big_page ? "2MB" : "4KB"));
            end
            // synthesis translate_on
        end
    end

endmodule // mpf_svc_vtp_pt_sw
