require "test_helper"

class VmControllerTest < ActionDispatch::IntegrationTest
  test "should get transaction" do
    get vm_transaction_url
    assert_response :success
  end

  test "should get create_block" do
    get vm_create_block_url
    assert_response :success
  end

  test "should get list_blocks" do
    get vm_list_blocks_url
    assert_response :success
  end

  test "should get get_contract" do
    get vm_get_contract_url
    assert_response :success
  end

  test "should get call_contract" do
    get vm_call_contract_url
    assert_response :success
  end
end
