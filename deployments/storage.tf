# Storage pools for Incus

resource "incus_storage_pool" "ultra" {
  name   = "ultra"
  driver = "lvm"

  config = {
    "source"              = "vg_ultra"
    "lvm.thinpool_name"   = "pool"
    "lvm.use_thinpool"    = "true"
    "lvm.vg.force_reuse"  = "true"
  }
}

resource "incus_storage_pool" "local_vg" {
  name   = "local_vg"
  driver = "lvm"

  config = {
    "source"              = "vg_local"
    "lvm.thinpool_name"   = "pool"
    "lvm.use_thinpool"    = "true"
    "lvm.vg.force_reuse"  = "true"
  }
}
