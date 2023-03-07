use anchor_lang::prelude::*;

// TODO ensure that metaplex makes all the necessary checks:
// * that all the remaining accounts are actually associated with each other in the right fashion

pub mod instructions;
pub mod instance;
pub mod error;

use instructions::*;

declare_id!("DxPDCoSdg5DWqE89uKh6qpsergPX8nd7DLH5EmyWY5uq");

#[program]
pub mod dust_bridging {
  use super::*;

  pub fn initialize(
    ctx: Context<Initialize>,
    collection_size: u16,
  ) -> Result<()> {
    instructions::initialize(ctx, collection_size)
  }

  pub fn burn_and_send(
    ctx: Context<BurnAndSend>,
    batch_id: u32,
    //can't use EvmAddress type because anchor program macro doesn't resolve it
    evm_recipient: [u8; 20], //EvmAddress
  ) -> Result<()> {
    instructions::burn_and_send(ctx, batch_id, &evm_recipient)
  }

  pub fn whitelist(
    ctx: Context<Whitelist>,
    token_ids: Vec<u16>,
  ) -> Result<()> {
    instructions::whitelist(ctx, token_ids)
  }

  pub fn whitelist_bulk(
    ctx: Context<Whitelist>,
    offset: u16,
    slice: Vec<u8>,
  ) -> Result<()> {
    instructions::whitelist_bulk(ctx, offset, slice)
  }

  pub fn set_delegate(
    ctx: Context<SetDelegate>,
    delegate: Option<Pubkey>,
  ) -> Result<()> {
    instructions::set_delegate(ctx, delegate)
  }

  pub fn set_paused(
    ctx: Context<SetPaused>,
    is_paused: bool,
  ) -> Result<()> {
    instructions::set_paused(ctx, is_paused)
  }
}
