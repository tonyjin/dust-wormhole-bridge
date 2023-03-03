pub mod accounts;
pub mod instructions;

pub mod program {
  use anchor_lang::prelude::*;
  pub use mpl_token_metadata::{ID, id};

  #[derive(Debug, Clone)]
  pub struct Metadata;

  impl Id for Metadata {
    fn id() -> Pubkey {
      ID
    }
  }
}