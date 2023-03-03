//naming this file state instead of accounts because accounts clashes with anchor macro

use anchor_lang::prelude::*;
use std::mem::size_of;

#[account]
#[derive(Default)]
/// Instance account doubles as emitter
pub struct Instance {
  pub bump: u8, //required for signing with the instance account
  pub collection_mint: Pubkey, //a seed of the instance account and thus also required for signing
  pub collection_meta: Pubkey,
}

impl Instance {
  pub const SIZE: usize
    = size_of::<[u8; 8]>() // discriminator
    + size_of::<u8>()      // bump
    + size_of::<Pubkey>()  // collection_mint
    + size_of::<Pubkey>()  // collection_meta
  ;

  pub const SEED_PREFIX: &'static [u8; 8] = b"instance";
}
