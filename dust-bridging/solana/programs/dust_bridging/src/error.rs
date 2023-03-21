use anchor_lang::prelude::error_code;

#[error_code]
pub enum DeBridgeError {
    #[msg("NotYetWhitelisted")]
    NotYetWhitelisted,
    #[msg("TokenIdOutOfBounds")]
    TokenIdOutOfBounds,
}