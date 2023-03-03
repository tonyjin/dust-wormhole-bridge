// TODO ensure that metaplex makes all the necessary checks:
// * that the nft is actually a verified part of the collection
// * that all the remaining accounts are actually associated with each other in the right fashion

use anchor_lang::prelude::*;
use anchor_spl::token::{Mint, Token};
use wormhole_anchor_sdk::wormhole;
use metaplex_anchor_sdk::{
  metadata,
  metadata::{
    program::ID as METADATA_ID,
    accounts::Metadata,
    instructions::{burn_nft, BurnNft},
  },
};

use crate::state::Instance;

//anchor_spl does not provide this constant itself...
pub const SEED_PREFIX_METADATA: &[u8; 8] = b"metadata";
pub const SEED_PREFIX_MESSAGE: &[u8; 7] = b"message";

pub type EvmAddress = [u8; 20];

#[derive(AnchorSerialize)]
struct Message<'a> {
  token_id: u16,
  evm_recipient: &'a EvmAddress,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
  #[account(
    init,
    payer = payer,
    space = Instance::SIZE,
    seeds = [Instance::SEED_PREFIX.as_ref(), &collection_mint.key().to_bytes()],
    bump,
  )]
  pub instance: Account<'info, Instance>,

  #[account(mut)]
  pub payer: Signer<'info>,

  #[account(mut)]
  pub admin: Signer<'info>,

  #[account()]
  pub collection_mint: Account<'info, Mint>,

  #[account(
    //metaplex unnecessarily includes the program id of the metadata program in its PDA seeds...
    seeds = [SEED_PREFIX_METADATA, &METADATA_ID.to_bytes(), &collection_mint.key().to_bytes()],
    bump,
    seeds::program = METADATA_ID,
    constraint = collection_meta.update_authority == admin.key(),
  )]
  //WARNING: anchor_spl does not check that the metadata has actually been initialized!
  pub collection_meta: Account<'info, Metadata>,

  pub system_program: Program<'info, System>,
}

pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
  let accs = ctx.accounts;
  let instance = &mut accs.instance;
  
  instance.bump = *ctx.bumps.get("instance").unwrap();
  instance.collection_mint = accs.collection_mint.key();
  instance.collection_meta = accs.collection_meta.key();

  Ok(())
}

#[derive(Accounts)]
pub struct BurnAndSend<'info> {
  #[account(
    mut,
    //This is the only check we have to do ourselves to ensure that the submitted NFT actually
    // belongs to the collection that our instance is associated with and hence that one can only
    // burn NFTs that are actually certified parts of that collection.
    //
    //The metaplex metadata program will take care of all other checks, namely that:
    // * The NFT token is actually associated with the mint.
    // * The mint is actually associated with the master edition.
    // * The mint is actually associated with the metadata.
    // * The metadata is actually a verified part of the collection.
    has_one = collection_meta,
  )]
  pub instance: Account<'info, Instance>,

  #[account(mut)]
  pub payer: Signer<'info>,

  #[account(mut)]
  pub nft_owner: Signer<'info>,

  #[account(mut)]
  /// CHECK: account will be checked by the metaplex metadata program
  pub nft_token: UncheckedAccount<'info>,

  #[account(mut)]
  /// CHECK: account will be checked by the metaplex metadata program
  pub nft_mint: UncheckedAccount<'info>,

  #[account(mut)]
  //we need the uri of the nft thus we have to deserialize its metadata
  //we have to box the account as to not exceed max stack offset of 4k
  /// CHECK: account will be checked by the metaplex metadata program
  pub nft_meta: Box<Account<'info, Metadata>>,

  #[account(mut)]
  /// CHECK: account will be checked by the metaplex metadata program
  pub nft_masteredition: UncheckedAccount<'info>,

  #[account(mut)]
  /// CHECK: account will be checked by the metaplex metadata program
  pub collection_meta: UncheckedAccount<'info>,

  #[account(
    mut,
    seeds = [SEED_PREFIX_MESSAGE, &nft_mint.key().to_bytes()],
    bump,
  )]
  /// CHECK: initialized and written to by wormhole core bridge
  pub wormhole_message: UncheckedAccount<'info>,

  #[account(mut)]
  /// CHECK: address will be checked by the wormhole core bridge
  pub wormhole_bridge: Account<'info, wormhole::BridgeData>,

  #[account(mut)]
  /// CHECK: account will be checked by the wormhole core bridge
  pub wormhole_fee_collector: UncheckedAccount<'info>,

  #[account(mut)]
  /// CHECK: account will be checked and maybe initialized by the wormhole core bridge
  pub wormhole_sequence: UncheckedAccount<'info>,

  pub wormhole_program: Program<'info, wormhole::program::Wormhole>,
  pub metadata_program: Program<'info, metadata::program::Metadata>,
  pub token_program: Program<'info, Token>,
  pub system_program: Program<'info, System>,
  
  //Wormhole was written before these could be requested from the runtime and so it's sadly
  // tech debt that's leaking out to us now (no way to request account infos)
  pub clock: Sysvar<'info, Clock>,
  pub rent: Sysvar<'info, Rent>,
}

pub fn burn_and_send(
  ctx: Context<BurnAndSend>,
  batch_id: u32,
  evm_recipient: &EvmAddress
) -> Result<()> {
  let accs = ctx.accounts;

  // 1. extract the token id from the metadata uri
  let token_id = {
    //DeGods uri example: https://metadata.degods.com/g/3250.json
    //y00ts uri example: https://metadata.y00ts.com/y/67.json
    let uri = &accs.nft_meta.data.uri;
    let start = uri.rfind('/').unwrap() + 1;
    //we can't use `let end = uri.len() - ".json".len();` because the uri is right padded
    let end = uri.find(".json").unwrap();
    uri[start..end].parse().unwrap()
  };

  // 2. burn the nft
  burn_nft(
    CpiContext::new(
      accs.metadata_program.to_account_info(),
      BurnNft {
        metadata: accs.nft_meta.to_account_info(),
        owner: accs.nft_owner.to_account_info(),
        mint: accs.nft_mint.to_account_info(),
        token: accs.nft_token.to_account_info(),
        master_edition: accs.nft_masteredition.to_account_info(),
        token_program: accs.token_program.to_account_info(),
        collection_metadata: accs.collection_meta.to_account_info(),
      },
    )
  )?;

  // 3. transfer Wormhole fee to fee collector account
  if accs.wormhole_bridge.fee() > 0 {
    anchor_lang::system_program::transfer(
      CpiContext::new(
        accs.system_program.to_account_info(),
        anchor_lang::system_program::Transfer {
          from: accs.payer.to_account_info(),
          to: accs.wormhole_fee_collector.to_account_info(),
        }
      ),
      accs.wormhole_bridge.fee(),
    )?;
  }
  
  // 4. emit the token id and intended evm recipient via wormhole
  let message_bump = ctx.bumps.get("wormhole_message").unwrap();

  wormhole::post_message(
    CpiContext::new_with_signer(
      accs.wormhole_program.to_account_info(),
      wormhole::PostMessage {
        config: accs.wormhole_bridge.to_account_info(),
        message: accs.wormhole_message.to_account_info(),
        emitter: accs.instance.to_account_info(),
        sequence: accs.wormhole_sequence.to_account_info(),
        payer: accs.payer.to_account_info(),
        fee_collector: accs.wormhole_fee_collector.to_account_info(),
        clock: accs.clock.to_account_info(),
        rent: accs.rent.to_account_info(),
        system_program: accs.system_program.to_account_info(),
      },
      &[
        &[
          Instance::SEED_PREFIX,
          &accs.instance.collection_mint.key().to_bytes(),
          &[accs.instance.bump]
        ],
        &[SEED_PREFIX_MESSAGE, &accs.nft_mint.key().to_bytes(), &[*message_bump]],
      ],
    ),
    batch_id,
    Message { token_id, evm_recipient }.try_to_vec()?, //.unwrap(),
    wormhole::Finality::Finalized,
  )?;

  // 5. log info to allow easy recovery of all involved accounts
  let wormhole_sequence =
    wormhole::SequenceTracker::try_from_slice(*accs.wormhole_sequence.data.borrow())
    .unwrap().value();
  msg!("nft mint: {}", accs.nft_mint.key());
  msg!("token id: {}", token_id);
  msg!("wormhole sequence: {}", wormhole_sequence);

  Ok(())
}

