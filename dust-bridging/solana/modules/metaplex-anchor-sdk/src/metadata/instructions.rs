use anchor_lang::prelude::*;

//this should help cut down on the insane amount of boilerplate
macro_rules! invoke_signed {
  ($ix_name:ident, $ctx:expr, $( $ix_arg:expr ),* $(,)?) => {
    {
      let ctx = &($ctx);
      let ix = mpl_token_metadata::instruction::$ix_name(
        mpl_token_metadata::ID,
        $( $ix_arg, )*
      );

      anchor_lang::solana_program::program::invoke_signed(
        &ix,
        &ToAccountInfos::to_account_infos(ctx),
        ctx.signer_seeds,
      ).map_err(Into::into)
    }
  };
}

#[derive(Accounts)]
pub struct BurnNft<'info> {
  pub metadata: AccountInfo<'info>,
  pub owner: AccountInfo<'info>,
  pub mint: AccountInfo<'info>,
  pub token: AccountInfo<'info>,
  pub master_edition: AccountInfo<'info>,
  pub token_program: AccountInfo<'info>,
  pub collection_metadata: AccountInfo<'info>,
}

pub fn burn_nft<'info>(
  ctx: CpiContext<'_, '_, '_, 'info, BurnNft<'info>>,
) -> Result<()> {
  invoke_signed!(
    burn_nft,
    ctx,
    *ctx.accounts.metadata.key,
    *ctx.accounts.owner.key,
    *ctx.accounts.mint.key,
    *ctx.accounts.token.key,
    *ctx.accounts.master_edition.key,
    *ctx.accounts.token_program.key,
    Some(*ctx.accounts.collection_metadata.key),
  )
}