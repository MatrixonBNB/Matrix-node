require 'rails_helper'

RSpec.describe "FacetSwapRouterV099 contract" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user_address) { "0xc2172a6315c1d7f6855768f843c420ebb36eda97".downcase }
  let(:token_a) { "0x1000000000000000000000000000000000000000" }
  let(:token_b) { "0x2000000000000000000000000000000000000000" }
  let(:weth_address) { "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }

  def sqrt(integer)
    Math.sqrt(integer.to_d).floor
  end

  it 'performs a token swap' do
    tokenA_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'contracts/StubERC20',
      from: user_address,
      args: ["Token A"]
    )
# binding.pry
    token_a_address = tokenA_deploy_receipt.contract_address
    
    factory_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'legacy/FacetSwapFactoryVe7f',
      from: user_address,
      args: [user_address]
    )
    
    factory_address = factory_deploy_receipt.contract_address

    tokenB_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'contracts/StubERC20',
      from: user_address,
      args: ["Token B"]
    )
    token_b_address = tokenB_deploy_receipt.contract_address

    router_deploy_receipt = deploy_contract_with_proxy(
      implementation: 'legacy/FacetSwapRouterV099',
      from: user_address,
      args: [factory_address, weth_address]
    )
    
    router_address = router_deploy_receipt.contract_address

    deploy_receipts = {
      "tokenA": tokenA_deploy_receipt,
      "tokenB": tokenB_deploy_receipt,
    }.with_indifferent_access

    create_pair_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: factory_address,
        data: {
          function: "createPair",
          args: {
            tokenA: deploy_receipts[:tokenA].contract_address,
            tokenB: deploy_receipts[:tokenB].contract_address
          }
        }
      }
    )
# binding.pry
    pair_address = create_pair_receipt.decoded_logs.detect { |i| i['event'] == 'PairCreated' }['data']['pair']
    TransactionHelper.contract_addresses[pair_address] = "legacy/FacetSwapPairV2b2"

    make_static_call(
      contract: pair_address,
      function_name: "sqrt",
      function_args: [100000000000000000000000000000000000000]
    )
    
    [:tokenA, :tokenB].each do |token|
      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          to: deploy_receipts[token].contract_address,
          data: {
            function: "mint",
            args: {
              amount: 100_000.ether
            }
          }
        }
      )

      trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          to: deploy_receipts[token].contract_address,
          data: {
            function: "approve",
            args: {
              spender: router_address,
              amount: (2 ** 256 - 1)
            }
          }
        }
      )
    end

    trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: pair_address,
        data: {
          function: "approve",
          args: {
            spender: router_address,
            amount: (2 ** 256 - 1)
          }
        }
      }
    )

    amountADesired = 5_000.ether
    amountBDesired = 5_000.ether - 2_000.ether
    amountAMin = 1_000.ether
    amountBMin = 1_000.ether

    add_liquidity_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "addLiquidity",
          args: {
            tokenA: token_a_address,
            tokenB: token_b_address,
            amountADesired: amountADesired,
            amountBDesired: amountBDesired,
            amountAMin: amountAMin,
            amountBMin: amountBMin,
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )

    lp_balance = make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )
# binding.pry
    expect(lp_balance).to eq(sqrt(amountADesired * amountBDesired) - 1000)

    my_current_liquidity = make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    liquidity_to_remove = my_current_liquidity.div(2)  # remove 50% of liquidity

    reserves = make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )

    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")

    total_lp_supply = make_static_call(
      contract: pair_address,
      function_name: "totalSupply"
    )

    my_share = liquidity_to_remove.div(total_lp_supply)

    amountA_estimated = my_share * reserveA
    amountB_estimated = my_share * reserveB

    acceptable_slippage = 0.01  # 1% slippage
    amountAMin = (amountA_estimated * (1 - acceptable_slippage)).to_i
    amountBMin = (amountB_estimated * (1 - acceptable_slippage)).to_i

    # Get the initial LP token balance and token balances
    initial_lp_balance = make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    initial_token_a_balance = make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    initial_token_b_balance = make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    remove_liquidity_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "removeLiquidity",
          args: {
            tokenA: token_a_address,
            tokenB: token_b_address,
            liquidity: liquidity_to_remove,
            amountAMin: amountAMin,
            amountBMin: amountBMin,
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )

    # Check final balances
    final_lp_balance = make_static_call(
      contract: pair_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    final_token_a_balance = make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    final_token_b_balance = make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    # Validate LP tokens are burned
    expect(final_lp_balance).to eq(initial_lp_balance - liquidity_to_remove)

    # Validate received amounts for tokenA and tokenB
    expect(final_token_a_balance - initial_token_a_balance).to be >= amountAMin
    expect(final_token_b_balance - initial_token_b_balance).to be >= amountBMin

    token_a_balance_before = make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    token_b_balance_before = make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    reserves = make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )

    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")

    amountIn = 1_000.ether
    amountOutMin = 300.ether

    numerator = amountIn * 997 * reserveB
    denominator = (reserveA * 1000) + (amountIn * 997)
    expectedOut = numerator.div(denominator)

    swap_receipt = trigger_contract_interaction_and_expect_success(
      from: user_address,
      payload: {
        to: router_address,
        data: {
          function: "swapExactTokensForTokens",
          args: {
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            path: [token_a_address, token_b_address],
            to: user_address,
            deadline: Time.now.to_i + 300
          }
        }
      }
    )

    token_a_balance_after = make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    token_b_balance_after = make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    token_a_diff = token_a_balance_after - token_a_balance_before
    expect(token_a_diff).to eq(-1 * amountIn)

    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(expectedOut)

    token_a_balance_before = make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    token_b_balance_before = make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    reserves = make_static_call(
      contract: router_address,
      function_name: "getReserves",
      function_args: [factory_address, token_a_address, token_b_address]
    )

    reserveA, reserveB = reserves.values_at("reserveA", "reserveB")

    amountOut = 300.ether
    amountInMax = 3_000.ether

    numerator = reserveA * amountOut * 1000
    denominator = (reserveB - amountOut) * 997
    expectedIn = (numerator.div(denominator)) + 1

    swap_receipt = nil

    t = Benchmark.ms do
      swap_receipt = trigger_contract_interaction_and_expect_success(
        from: user_address,
        payload: {
          to: router_address,
          data: {
            function: "swapTokensForExactTokens",
            args: {
              amountOut: amountOut,
              amountInMax: amountInMax,
              path: [token_a_address, token_b_address],
              to: user_address,
              deadline: Time.now.to_i + 300
            }
          }
        }
      )
    end

    token_a_balance_after = make_static_call(
      contract: token_a_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    token_b_balance_after = make_static_call(
      contract: token_b_address,
      function_name: "balanceOf",
      function_args: user_address
    )

    token_a_diff = token_a_balance_before - token_a_balance_after
    expect(token_a_diff).to eq(expectedIn)

    token_b_diff = token_b_balance_after - token_b_balance_before
    expect(token_b_diff).to eq(amountOut)
  end
end
