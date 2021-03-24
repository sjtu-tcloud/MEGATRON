#include "afu.h"
#include "optimus.h"

static inline uint64_t hash_func(uint64_t v) 
{
    return v >> 21;
}
static inline uint64_t aligned_2m(uint64_t v)
{
    return (v >> 21) << 21;
}
int hash_pt_init(struct optimus* optimus) 
{
    //hash_init(optimus->hash_pt);
    optimus->hash_pt = kzalloc(sizeof(hash_pt_node)*4096, GFP_KERNEL);
    if (!optimus->hash_pt) 
        optimus_info("error hash pt\n");
    return 0;
}
int hash_pt_uinit(struct optimus* optimus)
{
    kfree(optimus->hash_pt);
    return 0;
}
int hash_pt_insert_mapping(struct optimus * optimus, uint64_t va, uint64_t pa, uint64_t pg_size)
{
    uint64_t key = hash_func(va);
    //optimus_info("insert key: %llu\n", key);
    hash_pt_node *pt =optimus->hash_pt;
    pt[key].va = aligned_2m(va);
    pt[key].pa = pa;
    pt[key].pg_size = pg_size;
    /*hash_pt_node *entry = kzalloc(sizeof(hash_pt_node), GFP_KERNEL);
    entry->va = aligned_2m(va);
    entry->pa = pa;
    entry->pg_size = pg_size;
    hash_add(optimus->hash_pt, &entry->node, hash_func(va));*/
    return 0;
}

int hash_pt_remove_mapping(struct optimus * optimus, hash_pt_node *pt_node)
{
    //hash_del(&pt_node->node);
    
    return 0;
}

uint64_t hash_pt_iova_to_hpa(struct optimus* optimus, uint64_t iova, uint64_t *pg_size)//, hash_pt_node** p_pt_node)
{
    uint64_t key = hash_func(iova);
    hash_pt_node *pt = optimus->hash_pt;
    //optimus_info("translate key: %llu\n", key);
    if (pg_size) *pg_size = pt[key].pg_size;
    return pt[key].pa;
    /*hash_pt_node *entry;
    uint64_t aligned_iova = aligned_2m(iova);
    hash_for_each_possible(optimus->hash_pt, entry, node, hash_func(iova)) {
        if (entry->va == aligned_iova) {
            if (p_pt_node) {
                *p_pt_node = entry;
            }
            if (pg_size){
                *pg_size = entry->pg_size;
            }
            return entry->pa;
        }
    }
    return 0;*/
}
