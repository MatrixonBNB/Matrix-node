require "rails_helper"

RSpec.describe "FacetSwapV1Factory" do
  include ActiveSupport::Testing::TimeHelpers

  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }
  let(:from_address) { "0xC2172a6315c1D7f6855768F843c420EbB36eDa97".downcase }
  let(:token_a) { "0x1000000000000000000000000000000000000000" }
  let(:token_b) { "0x2000000000000000000000000000000000000000" }

  it 'creates a new pair successfully' do
    factory_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'legacy/FacetSwapFactoryVe7f',
      from: from_address,
      args: [from_address]
    )
    
    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: from_address,
      payload: {
        to: factory_deploy_receipt.contract_address,
        data: {
          function: "createPair",
          args: {
            tokenA: token_a,
            tokenB: token_b
          }
        }
      }
    )
# binding.pry
    all_pairs_length = make_static_call(
      contract: factory_deploy_receipt.contract_address,
      function_name: "allPairsLength"
    )

    all_pairs = make_static_call(
      contract: factory_deploy_receipt.contract_address,
      function_name: "getAllPairs"
    )
# binding.pry
#     expect(create_pair_receipt.decoded_logs).to include(
#       hash_including('event' => 'PairCreated')
#     )
  end

  it 'throws error when creating pair with identical tokens' do
    factory_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'legacy/FacetSwapFactoryVe7f',
      from: from_address,
      args: [from_address]
    )

    trigger_contract_interaction_and_expect_error(
      # error_msg_includes: 'FacetSwapV1: IDENTICAL_ADDRESSES',
      from: from_address,
      payload: {
        to: factory_deploy_receipt.contract_address,
        data: {
          function: "createPair",
          args: {
            tokenA: token_a,
            tokenB: token_a # Same address to trigger the error
          }
        }
      }
    )
  end

  it 'throws error when creating pair that already exists' do
    factory_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'legacy/FacetSwapFactoryVe7f',
      from: from_address,
      args: [from_address]
    )

    trigger_contract_interaction_and_expect_success(
      from: from_address,
      payload: {
        to: factory_deploy_receipt.contract_address,
        data: {
          function: "createPair",
          args: {
            tokenA: token_a,
            tokenB: token_b
          }
        }
      }
    )

    trigger_contract_interaction_and_expect_error(
      # error_msg_includes: 'FacetSwapV1: PAIR_EXISTS',
      from: from_address,
      payload: {
        to: factory_deploy_receipt.contract_address,
        data: {
          function: "createPair",
          args: {
            tokenA: token_a,
            tokenB: token_b
          }
        }
      }
    )
  end
end
