import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

const contractName = 'NativeStargateComposer'

const STARGATE_POOL_NATIVE_ARBITRUM = {
    testnet: '0x6fddB6270F6c71f31B62AE0260cfa8E2e2d186E0',
    mainnet: '0xA45B5130f36CDcA45667738e2a258AB09f4A5f7F',
}

const stargatePoolNative = STARGATE_POOL_NATIVE_ARBITRUM.testnet // NOTE: update to mainnet if deploying to mainnet

const deploy: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre

    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    assert(deployer, 'Missing named deployer account')

    console.log(`Network: ${hre.network.name}`)
    console.log(`Deployer: ${deployer}`)

    // Get the NativeOFTAdapter deployment (must be deployed first)
    const nativeOFTAdapterDeployment = await hre.deployments.get('MyNativeOFTAdapter')

    assert(
        stargatePoolNative !== '0x0000000000000000000000000000000000000000',
        'STARGATE_POOL_NATIVE address not set. Please update the constant in this file.'
    )

    console.log(`NativeOFTAdapter: ${nativeOFTAdapterDeployment.address}`)
    console.log(`Stargate PoolNative: ${stargatePoolNative}`)
    console.log(`Executor (refund recipient): ${deployer}`)

    const { address } = await deploy(contractName, {
        from: deployer,
        args: [
            nativeOFTAdapterDeployment.address, // NativeOFTAdapter address
            stargatePoolNative, // Stargate PoolNative address
            deployer, // Executor for refunds
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    })

    console.log(`Deployed contract: ${contractName}, network: ${hre.network.name}, address: ${address}`)
}

deploy.tags = [contractName]
deploy.dependencies = ['MyNativeOFTAdapter'] // Ensure NativeOFTAdapter is deployed first

export default deploy
