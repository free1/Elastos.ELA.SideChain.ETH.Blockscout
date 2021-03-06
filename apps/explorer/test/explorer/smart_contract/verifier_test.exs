defmodule Explorer.SmartContract.VerifierTest do
  use ExUnit.Case, async: true
  use Explorer.DataCase

  doctest Explorer.SmartContract.Verifier

  alias Explorer.SmartContract.Verifier
  alias Explorer.Factory

  describe "evaluate_authenticity/2" do
    setup do
      {:ok, contract_code_info: Factory.contract_code_info()}
    end

    test "verifies the generated bytecode against bytecode retrieved from the blockchain", %{
      contract_code_info: contract_code_info
    } do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      params = %{
        "contract_source_code" => contract_code_info.source_code,
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies the generated bytecode with external libraries" do
      contract_data =
        "#{File.cwd!()}/test/support/fixture/smart_contract/compiler_tests.json"
        |> File.read!()
        |> Jason.decode!()
        |> List.first()

      compiler_version = contract_data["compiler_version"]
      external_libraries = contract_data["external_libraries"]
      name = contract_data["name"]
      optimize = contract_data["optimize"]
      contract = contract_data["contract"]
      expected_bytecode = contract_data["expected_bytecode"]

      contract_address = insert(:contract_address, contract_code: "0x" <> expected_bytecode)

      params = %{
        "contract_source_code" => contract,
        "compiler_version" => compiler_version,
        "name" => name,
        "optimization" => optimize,
        "external_libraries" => external_libraries
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies smart contract with new `whisper` metadata (bzz0 => bzz1) in solidity 0.5.11" do
      contract_data =
        "#{File.cwd!()}/test/support/fixture/smart_contract/solidity_5.11_new_whisper_metadata.json"
        |> File.read!()
        |> Jason.decode!()

      compiler_version = contract_data["compiler_version"]
      name = contract_data["name"]
      optimize = false
      contract = contract_data["contract"]
      expected_bytecode = contract_data["bytecode"]
      evm_version = contract_data["evm_version"]

      contract_address = insert(:contract_address, contract_code: "0x" <> expected_bytecode)

      params = %{
        "contract_source_code" => contract,
        "compiler_version" => compiler_version,
        "evm_version" => evm_version,
        "name" => name,
        "optimization" => optimize
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies smart contract with constructor arguments", %{
      contract_code_info: contract_code_info
    } do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      constructor_arguments = "0102030405"

      params = %{
        "contract_source_code" => contract_code_info.source_code,
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized,
        "constructor_arguments" => constructor_arguments
      }

      :transaction
      |> insert(
        created_contract_address_hash: contract_address.hash,
        input: contract_code_info.bytecode <> constructor_arguments
      )
      |> with_block()

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "tries to compile with the latest evm version if wrong evm version was provided" do
      bytecode =
        "0x60606040526000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff168063256fec88146100545780633fa4f245146100a9578063812600df146100d2575b600080fd5b341561005f57600080fd5b6100676100f5565b604051808273ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200191505060405180910390f35b34156100b457600080fd5b6100bc61011b565b6040518082815260200191505060405180910390f35b34156100dd57600080fd5b6100f36004808035906020019091905050610121565b005b600160009054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b60005481565b806000540160008190555033600160006101000a81548173ffffffffffffffffffffffffffffffffffffffff021916908373ffffffffffffffffffffffffffffffffffffffff1602179055505b505600a165627a7a72305820b81379d1ae9d8e0fde05ee02b8bd170f43f8bd3d54da8b7ec203434a23a298980029"

      contract_address = insert(:contract_address, contract_code: bytecode)

      code = """
      pragma solidity ^0.4.15;
      contract Incrementer {
          event Incremented(address indexed sender, uint256 newValue);
          uint256 public value;
          address public lastSender;
          function Incrementer(uint256 initialValue) {
              value = initialValue;
              lastSender = msg.sender;
          }
          function inc(uint256 delta) {
              value = value + delta;
              lastSender = msg.sender;
          }
      }
      """

      params = %{
        "contract_source_code" => code,
        "compiler_version" => "v0.4.15+commit.bbb8e64f",
        "evm_version" => "homestead",
        "name" => "Incrementer",
        "optimization" => false
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies a library" do
      bytecode =
        "0x7349f540c22cba15c47a08c235e20081474201a742301460806040526004361060335760003560e01c8063c2985578146038575b600080fd5b603e60b0565b6040805160208082528351818301528351919283929083019185019080838360005b8381101560765781810151838201526020016060565b50505050905090810190601f16801560a25780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b604080518082019091526003815262666f6f60e81b60208201529056fea265627a7a72315820174b282a3ef3b9778d79fbc2e4c36bc939c54dfaaaa51d3122ee6e648093844c64736f6c634300050b0032"

      contract_address = insert(:contract_address, contract_code: bytecode)

      code = """
      pragma solidity 0.5.11;

      library Foo {
          function foo() external pure returns (string memory) {
              return "foo";
          }
      }
      """

      params = %{
        "contract_source_code" => code,
        "compiler_version" => "v0.5.11+commit.c082d0b4",
        "evm_version" => "default",
        "name" => "Foo",
        "optimization" => true
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "verifies smart contract compiled with Solidity 0.5.9 (includes new metadata in bytecode) with constructor args" do
      path = File.cwd!() <> "/test/support/fixture/smart_contract/solidity_0.5.9_smart_contract.sol"
      contract = File.read!(path)

      constructor_arguments =
        "00000000000000000000000000000000000000000000003635c9adc5dea000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000a54657374546f6b656e32000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006546f6b656e320000000000000000000000000000000000000000000000000000"

      bytecode =
        "0x608060405234801561001057600080fd5b50600436106100a95760003560e01c80633177029f116100715780633177029f1461025f57806354fd4d50146102c557806370a082311461034857806395d89b41146103a0578063a9059cbb14610423578063dd62ed3e14610489576100a9565b806306fdde03146100ae578063095ea7b31461013157806318160ddd1461019757806323b872dd146101b5578063313ce5671461023b575b600080fd5b6100b6610501565b6040518080602001828103825283818151815260200191508051906020019080838360005b838110156100f65780820151818401526020810190506100db565b50505050905090810190601f1680156101235780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b61017d6004803603604081101561014757600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291908035906020019092919050505061059f565b604051808215151515815260200191505060405180910390f35b61019f610691565b6040518082815260200191505060405180910390f35b610221600480360360608110156101cb57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050610696565b604051808215151515815260200191505060405180910390f35b61024361090f565b604051808260ff1660ff16815260200191505060405180910390f35b6102ab6004803603604081101561027557600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050610922565b604051808215151515815260200191505060405180910390f35b6102cd610a14565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561030d5780820151818401526020810190506102f2565b50505050905090810190601f16801561033a5780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b61038a6004803603602081101561035e57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610ab2565b6040518082815260200191505060405180910390f35b6103a8610afa565b6040518080602001828103825283818151815260200191508051906020019080838360005b838110156103e85780820151818401526020810190506103cd565b50505050905090810190601f1680156104155780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b61046f6004803603604081101561043957600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff16906020019092919080359060200190929190505050610b98565b604051808215151515815260200191505060405180910390f35b6104eb6004803603604081101561049f57600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803573ffffffffffffffffffffffffffffffffffffffff169060200190929190505050610cfe565b6040518082815260200191505060405180910390f35b60038054600181600116156101000203166002900480601f0160208091040260200160405190810160405280929190818152602001828054600181600116156101000203166002900480156105975780601f1061056c57610100808354040283529160200191610597565b820191906000526020600020905b81548152906001019060200180831161057a57829003601f168201915b505050505081565b600081600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a36001905092915050565b600090565b6000816000808673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410158015610762575081600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410155b801561076e5750600082115b1561090357816000808573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282540192505081905550816000808673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000828254039250508190555081600160008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a360019050610908565b600090505b9392505050565b600460009054906101000a900460ff1681565b600081600160003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a36001905092915050565b60068054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015610aaa5780601f10610a7f57610100808354040283529160200191610aaa565b820191906000526020600020905b815481529060010190602001808311610a8d57829003601f168201915b505050505081565b60008060008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020549050919050565b60058054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015610b905780601f10610b6557610100808354040283529160200191610b90565b820191906000526020600020905b815481529060010190602001808311610b7357829003601f168201915b505050505081565b6000816000803373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410158015610be85750600082115b15610cf357816000803373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008282540392505081905550816000808573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a360019050610cf8565b600090505b92915050565b6000600160008473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205490509291505056fea265627a7a72305820fe0ba5210ac95870683c2cb054304b04565703bd16c7d7e956df694c9643c6d264736f6c63430005090032"

      contract_address = insert(:contract_address, contract_code: bytecode)

      :transaction
      |> insert(
        created_contract_address_hash: contract_address.hash,
        input: bytecode <> constructor_arguments
      )
      |> with_block()

      params = %{
        "contract_source_code" => contract,
        "compiler_version" => "v0.5.9+commit.e560f70d",
        "evm_version" => "petersburg",
        "name" => "TestToken",
        "optimization" => false,
        "constructor_arguments" => constructor_arguments
      }

      assert {:ok, %{abi: abi}} = Verifier.evaluate_authenticity(contract_address.hash, params)
      assert abi != nil
    end

    test "returns error when bytecode doesn't match", %{contract_code_info: contract_code_info} do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      different_code = "pragma solidity ^0.4.24; contract SimpleStorage {}"

      params = %{
        "contract_source_code" => different_code,
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized
      }

      response = Verifier.evaluate_authenticity(contract_address.hash, params)

      assert {:error, :generated_bytecode} = response
    end

    test "returns error when there is a compilation problem", %{contract_code_info: contract_code_info} do
      contract_address = insert(:contract_address, contract_code: contract_code_info.bytecode)

      params = %{
        "contract_source_code" => "pragma solidity ^0.4.24; contract SimpleStorage { ",
        "compiler_version" => contract_code_info.version,
        "name" => contract_code_info.name,
        "optimization" => contract_code_info.optimized
      }

      assert {:error, :compilation} = Verifier.evaluate_authenticity(contract_address.hash, params)
    end
  end

  describe "extract_bytecode/1" do
    test "extracts the bytecode from the hash" do
      code =
        "0x608060405234801561001057600080fd5b5060df8061001f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600a165627a7a723058203c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b0029"

      swarm_source = "3c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b"

      bytecode =
        "0x608060405234801561001057600080fd5b5060df8061001f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600"

      assert bytecode == Verifier.extract_bytecode(code)
      assert bytecode != code
      assert String.contains?(code, bytecode) == true
      assert String.contains?(bytecode, "0029") == false
      assert String.contains?(bytecode, swarm_source) == false
    end

    test "extracts everything to the left of the swarm hash" do
      code =
        "0x608060405234801561001057600080fd5b5060df80610010029f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600a165627a7a723058203c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b0029"

      swarm_source = "3c381c1b48b38d050c54d7ef296ecd411040e19420dfec94772b9c49ae106a0b"

      bytecode =
        "0x608060405234801561001057600080fd5b5060df80610010029f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600"

      assert bytecode == Verifier.extract_bytecode(code)
      assert bytecode != code
      assert String.contains?(code, bytecode) == true
      assert String.contains?(bytecode, "0029") == true
      assert String.contains?(bytecode, swarm_source) == false
    end
  end
end
