import { EndpointId } from '@layerzerolabs/lz-definitions'

import type { OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

/**
 *  WARNING: ONLY 1 NativeOFTAdapter should exist for a given global mesh.
 */
const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBSEP_V2_TESTNET,
    contractName: 'MyNativeOFTAdapter',
}

const optimismContract: OmniPointHardhat = {
    eid: EndpointId.OPTSEP_V2_TESTNET,
    contractName: 'MyOFT',
}


const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: optimismContract,
        },
        {
            contract: arbitrumContract,
        },
    ],
    connections: [
        {
            from: optimismContract,
            to: arbitrumContract,
        },
        {
            from: arbitrumContract,
            to: optimismContract,
        }
    ],
}

export default config
