use anchor_lang::prelude::*;

pub use instructions::*;
pub use state::*;

pub mod instructions;
pub mod state;

declare_id!("DxPDCoSdg5DWqE89uKh6qpsergPX8nd7DLH5EmyWY5uq");

#[program]
pub mod dust_bridging {
  use super::*;

  pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
    instructions::initialize(ctx)
  }

  pub fn burn_and_send(
    ctx: Context<BurnAndSend>,
    batch_id: u32,
    //can't use EvmAddress type because anchor program macro doesn't resolve it
    evm_recipient: [u8; 20],
  ) -> Result<()> {
    instructions::burn_and_send(ctx, batch_id, &evm_recipient)
  }
}
