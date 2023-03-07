use anchor_lang::prelude::*;
use anchor_spl::token::Mint;
use metaplex_anchor_sdk::{
  metadata::{
    program::ID as METADATA_ID,
    accounts::Metadata,
  },
};

use crate::instance::Instance;

//anchor_spl does not provide these definitions itself...
pub const SEED_PREFIX_METADATA: &[u8; 8] = b"metadata";

const fn whitelist_bytes(collection_size: u16) -> usize {
  (collection_size/8 + if (collection_size % 8) > 0 {1} else {0}) as usize
}

#[derive(Accounts)]
#[instruction(collection_size: u16)]
pub struct Initialize<'info> {
  #[account(
    init,
    payer = payer,
    space = Instance::BASE_SIZE + whitelist_bytes(collection_size),
    seeds = [Instance::SEED_PREFIX.as_ref(), &collection_mint.key().to_bytes()],
    bump,
  )]
  pub instance: Account<'info, Instance>,

  #[account(mut)]
  pub payer: Signer<'info>,

  #[account(mut)]
  pub update_authority: Signer<'info>, //update authority of collection meta is admin of contract

  #[account()]
  pub collection_mint: Account<'info, Mint>,

  #[account(
    //metaplex unnecessarily includes the program id of the metadata program in its PDA seeds...
    seeds = [SEED_PREFIX_METADATA, &METADATA_ID.to_bytes(), &collection_mint.key().to_bytes()],
    bump,
    seeds::program = METADATA_ID,
    has_one = update_authority,
  )]
  //WARNING: anchor_spl does not check that the metadata has actually been initialized!
  pub collection_meta: Account<'info, Metadata>,

  pub system_program: Program<'info, System>,
}

/// collection_size = 0 disables whitelisting, otherwise token_id must be < collection_size
pub fn initialize(ctx: Context<Initialize>, collection_size: u16) -> Result<()> {
  let accs = ctx.accounts;
  let instance = &mut accs.instance;
  
  instance.bump = *ctx.bumps.get("instance").unwrap();
  instance.update_authority = accs.update_authority.key();
  instance.collection_mint = accs.collection_mint.key();
  instance.collection_meta = accs.collection_meta.key();
  instance.delegate = None;
  instance.is_paused = false;
  instance.collection_size = collection_size;
  instance.whitelist = vec![0; whitelist_bytes(collection_size)];

  Ok(())
}