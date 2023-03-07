use anchor_lang::prelude::*;

#[account]
/// Instance account doubles as emitter
pub struct Instance {
  pub bump: u8, //required for signing with the instance account
  pub update_authority: Pubkey,
  pub collection_mint: Pubkey, //a seed of the instance account and thus also required for signing
  pub collection_meta: Pubkey,
  pub delegate: Option<Pubkey>,
  pub is_paused: bool,
  pub collection_size: u16, // 0 means no whitelisting required
  pub whitelist: Vec<u8>,
}

impl Instance {
  //see https://www.anchor-lang.com/docs/space
  pub const BASE_SIZE: usize
    = 8      // anchor discriminator = [u8; 8]
    + 1      // bump
    + 32     // update_authority
    + 32     // collection_mint
    + 32     // collection_meta
    + 1 + 32 // delegate
    + 1      // is_paused
    + 2      // collection_size
    + 4      // whitelist
  ;

  pub const SEED_PREFIX: &'static [u8; 8] = b"instance";

  pub fn whitelist_enabled(&self) -> bool {
    self.collection_size > 0
  }

  pub fn is_whitelisted(&self, token_id: u16) -> bool {
    self.whitelist[token_id as usize / 8] & (1u8 << (token_id % 8)) > 0
  }
}