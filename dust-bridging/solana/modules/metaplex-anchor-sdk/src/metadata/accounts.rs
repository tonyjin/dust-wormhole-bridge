use anchor_lang::prelude::*;
use mpl_token_metadata::state::{Metadata as MplMetadata, TokenMetadataAccount};
use crate::metadata::program::ID;

#[derive(Clone)]
pub struct Metadata(MplMetadata);

impl Metadata {
  pub const SEED_PREFIX: &'static [u8; 8] = b"metadata";
  pub const LEN: usize = mpl_token_metadata::state::MAX_METADATA_LEN;
}

impl AccountDeserialize for Metadata {
  fn try_deserialize(buf: &mut &[u8]) -> Result<Self> {
    let md = Self::try_deserialize_unchecked(buf)?;
    if md.key != MplMetadata::key() {
      return Err(ErrorCode::AccountDiscriminatorMismatch.into());
    }
    Ok(md)
  }

  fn try_deserialize_unchecked(buf: &mut &[u8]) -> Result<Self> {
    Ok(Self(MplMetadata::deserialize(buf)?))
  }
}

//no-op since data can only be changed through metaplex's metadata program
impl AccountSerialize for Metadata {}

impl Owner for Metadata {
  fn owner() -> Pubkey {
    ID
  }
}

impl std::ops::Deref for Metadata {
  type Target = MplMetadata;

  fn deref(&self) -> &Self::Target {
    &self.0
  }
}
