use anchor_lang::prelude::error_code;

#[error_code]
pub enum DustBridgingError {
    #[msg("NotYetWhitelisted")]
    NotYetWhitelisted,
    #[msg("TokenIdOutOfBounds")]
    TokenIdOutOfBounds,
}