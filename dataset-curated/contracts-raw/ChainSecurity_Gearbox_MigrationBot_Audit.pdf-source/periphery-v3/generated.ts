//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IACLLegacy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iaclLegacyAbi = [
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'addPausableAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'addUnpausableAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'claimOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'isPausableAdmin',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'isUnpausableAdmin',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'owner',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'pendingOwner',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'removePausableAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'account', internalType: 'address', type: 'address' }],
    name: 'removeUnpausableAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'newOwner', internalType: 'address', type: 'address' }],
    name: 'transferOwnership',
    outputs: [],
    stateMutability: 'nonpayable',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IAdapterCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iAdapterCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'getAdapters',
    outputs: [
      {
        name: 'result',
        internalType: 'struct AdapterState[]',
        type: 'tuple[]',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'targetContract', internalType: 'address', type: 'address' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IAuraL2Coordinator
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iAuraL2CoordinatorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'auraOFT',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'mintRate',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IContractsRegisterLegacy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iContractsRegisterLegacyAbi = [
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'addCreditManager',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'addPool',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getCreditManagers',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getPools',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IConvexToken
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iConvexTokenAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'EMISSIONS_MAX_SUPPLY',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'maxSupply',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'reductionPerCliff',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalCliffs',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'totalSupply',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ICreditAccountCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iCreditAccountCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      {
        name: 'caFilter',
        internalType: 'struct CreditAccountFilter',
        type: 'tuple',
        components: [
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'includeZeroDebt', internalType: 'bool', type: 'bool' },
          { name: 'minHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'maxHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'reverting', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    name: 'countCreditAccounts',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'cmFilter',
        internalType: 'struct MarketFilter',
        type: 'tuple',
        components: [
          {
            name: 'configurators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'pools', internalType: 'address[]', type: 'address[]' },
          { name: 'underlying', internalType: 'address', type: 'address' },
        ],
      },
      {
        name: 'caFilter',
        internalType: 'struct CreditAccountFilter',
        type: 'tuple',
        components: [
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'includeZeroDebt', internalType: 'bool', type: 'bool' },
          { name: 'minHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'maxHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'reverting', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    name: 'countCreditAccounts',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditAccount', internalType: 'address', type: 'address' },
    ],
    name: 'getCreditAccountData',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditAccountData',
        type: 'tuple',
        components: [
          { name: 'creditAccount', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'healthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'success', internalType: 'bool', type: 'bool' },
          {
            name: 'tokens',
            internalType: 'struct TokenInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'mask', internalType: 'uint256', type: 'uint256' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'cmFilter',
        internalType: 'struct MarketFilter',
        type: 'tuple',
        components: [
          {
            name: 'configurators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'pools', internalType: 'address[]', type: 'address[]' },
          { name: 'underlying', internalType: 'address', type: 'address' },
        ],
      },
      {
        name: 'caFilter',
        internalType: 'struct CreditAccountFilter',
        type: 'tuple',
        components: [
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'includeZeroDebt', internalType: 'bool', type: 'bool' },
          { name: 'minHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'maxHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'reverting', internalType: 'bool', type: 'bool' },
        ],
      },
      { name: 'offset', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getCreditAccounts',
    outputs: [
      {
        name: 'data',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'creditAccount', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'healthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'success', internalType: 'bool', type: 'bool' },
          {
            name: 'tokens',
            internalType: 'struct TokenInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'mask', internalType: 'uint256', type: 'uint256' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
      { name: 'nextOffset', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      {
        name: 'caFilter',
        internalType: 'struct CreditAccountFilter',
        type: 'tuple',
        components: [
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'includeZeroDebt', internalType: 'bool', type: 'bool' },
          { name: 'minHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'maxHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'reverting', internalType: 'bool', type: 'bool' },
        ],
      },
      { name: 'offset', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getCreditAccounts',
    outputs: [
      {
        name: 'data',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'creditAccount', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'healthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'success', internalType: 'bool', type: 'bool' },
          {
            name: 'tokens',
            internalType: 'struct TokenInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'mask', internalType: 'uint256', type: 'uint256' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
      { name: 'nextOffset', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      {
        name: 'caFilter',
        internalType: 'struct CreditAccountFilter',
        type: 'tuple',
        components: [
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'includeZeroDebt', internalType: 'bool', type: 'bool' },
          { name: 'minHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'maxHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'reverting', internalType: 'bool', type: 'bool' },
        ],
      },
      { name: 'offset', internalType: 'uint256', type: 'uint256' },
      { name: 'limit', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getCreditAccounts',
    outputs: [
      {
        name: 'data',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'creditAccount', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'healthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'success', internalType: 'bool', type: 'bool' },
          {
            name: 'tokens',
            internalType: 'struct TokenInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'mask', internalType: 'uint256', type: 'uint256' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
      { name: 'nextOffset', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'cmFilter',
        internalType: 'struct MarketFilter',
        type: 'tuple',
        components: [
          {
            name: 'configurators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'pools', internalType: 'address[]', type: 'address[]' },
          { name: 'underlying', internalType: 'address', type: 'address' },
        ],
      },
      {
        name: 'caFilter',
        internalType: 'struct CreditAccountFilter',
        type: 'tuple',
        components: [
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'includeZeroDebt', internalType: 'bool', type: 'bool' },
          { name: 'minHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'maxHealthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'reverting', internalType: 'bool', type: 'bool' },
        ],
      },
      { name: 'offset', internalType: 'uint256', type: 'uint256' },
      { name: 'limit', internalType: 'uint256', type: 'uint256' },
    ],
    name: 'getCreditAccounts',
    outputs: [
      {
        name: 'data',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'creditAccount', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'owner', internalType: 'address', type: 'address' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'healthFactor', internalType: 'uint16', type: 'uint16' },
          { name: 'success', internalType: 'bool', type: 'bool' },
          {
            name: 'tokens',
            internalType: 'struct TokenInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'mask', internalType: 'uint256', type: 'uint256' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
      { name: 'nextOffset', internalType: 'uint256', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ICreditSuiteCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iCreditSuiteCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditFacade', internalType: 'address', type: 'address' },
    ],
    name: 'getCreditFacadeState',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditFacadeState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'degenNFT', internalType: 'address', type: 'address' },
          { name: 'botList', internalType: 'address', type: 'address' },
          { name: 'expirable', internalType: 'bool', type: 'bool' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          {
            name: 'maxDebtPerBlockMultiplier',
            internalType: 'uint8',
            type: 'uint8',
          },
          { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
          { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'forbiddenTokenMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'isPaused', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'getCreditManagerState',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditManagerState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'accountFactory', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'pool', internalType: 'address', type: 'address' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          {
            name: 'creditConfigurator',
            internalType: 'address',
            type: 'address',
          },
          { name: 'maxEnabledTokens', internalType: 'uint8', type: 'uint8' },
          {
            name: 'collateralTokens',
            internalType: 'struct CollateralToken[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              {
                name: 'liquidationThreshold',
                internalType: 'uint16',
                type: 'uint16',
              },
            ],
          },
          { name: 'feeInterest', internalType: 'uint16', type: 'uint16' },
          { name: 'feeLiquidation', internalType: 'uint16', type: 'uint16' },
          {
            name: 'liquidationDiscount',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'feeLiquidationExpired',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'liquidationDiscountExpired',
            internalType: 'uint16',
            type: 'uint16',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'getCreditSuiteData',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditSuiteData',
        type: 'tuple',
        components: [
          {
            name: 'creditFacade',
            internalType: 'struct CreditFacadeState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'creditManager',
                internalType: 'address',
                type: 'address',
              },
              { name: 'degenNFT', internalType: 'address', type: 'address' },
              { name: 'botList', internalType: 'address', type: 'address' },
              { name: 'expirable', internalType: 'bool', type: 'bool' },
              {
                name: 'expirationDate',
                internalType: 'uint40',
                type: 'uint40',
              },
              {
                name: 'maxDebtPerBlockMultiplier',
                internalType: 'uint8',
                type: 'uint8',
              },
              { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
              { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
              {
                name: 'forbiddenTokenMask',
                internalType: 'uint256',
                type: 'uint256',
              },
              { name: 'isPaused', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'creditManager',
            internalType: 'struct CreditManagerState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'name', internalType: 'string', type: 'string' },
              {
                name: 'accountFactory',
                internalType: 'address',
                type: 'address',
              },
              { name: 'underlying', internalType: 'address', type: 'address' },
              { name: 'pool', internalType: 'address', type: 'address' },
              {
                name: 'creditFacade',
                internalType: 'address',
                type: 'address',
              },
              {
                name: 'creditConfigurator',
                internalType: 'address',
                type: 'address',
              },
              {
                name: 'maxEnabledTokens',
                internalType: 'uint8',
                type: 'uint8',
              },
              {
                name: 'collateralTokens',
                internalType: 'struct CollateralToken[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  {
                    name: 'liquidationThreshold',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                ],
              },
              { name: 'feeInterest', internalType: 'uint16', type: 'uint16' },
              {
                name: 'feeLiquidation',
                internalType: 'uint16',
                type: 'uint16',
              },
              {
                name: 'liquidationDiscount',
                internalType: 'uint16',
                type: 'uint16',
              },
              {
                name: 'feeLiquidationExpired',
                internalType: 'uint16',
                type: 'uint16',
              },
              {
                name: 'liquidationDiscountExpired',
                internalType: 'uint16',
                type: 'uint16',
              },
            ],
          },
          {
            name: 'creditConfigurator',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'adapters',
            internalType: 'struct AdapterState[]',
            type: 'tuple[]',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'targetContract',
                internalType: 'address',
                type: 'address',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IDataCompressorV3
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iDataCompressorV3Abi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditAccount', internalType: 'address', type: 'address' },
      {
        name: 'priceUpdates',
        internalType: 'struct PriceUpdate[]',
        type: 'tuple[]',
        components: [
          { name: 'priceFeed', internalType: 'address', type: 'address' },
          { name: 'data', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'getCreditAccountData',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditAccountData',
        type: 'tuple',
        components: [
          { name: 'isSuccessful', internalType: 'bool', type: 'bool' },
          {
            name: 'priceFeedsNeeded',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'borrower', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'cmName', internalType: 'string', type: 'string' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'cumulativeIndexLastUpdate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'cumulativeQuotaInterest',
            internalType: 'uint128',
            type: 'uint128',
          },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'healthFactor', internalType: 'uint256', type: 'uint256' },
          { name: 'baseBorrowRate', internalType: 'uint256', type: 'uint256' },
          {
            name: 'aggregatedBorrowRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'balances',
            internalType: 'struct TokenBalance[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'isForbidden', internalType: 'bool', type: 'bool' },
              { name: 'isEnabled', internalType: 'bool', type: 'bool' },
              { name: 'isQuoted', internalType: 'bool', type: 'bool' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'quotaRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaCumulativeIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
            ],
          },
          { name: 'since', internalType: 'uint64', type: 'uint64' },
          { name: 'cfVersion', internalType: 'uint256', type: 'uint256' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          { name: 'activeBots', internalType: 'address[]', type: 'address[]' },
        ],
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'borrower', internalType: 'address', type: 'address' },
      {
        name: 'priceUpdates',
        internalType: 'struct PriceUpdate[]',
        type: 'tuple[]',
        components: [
          { name: 'priceFeed', internalType: 'address', type: 'address' },
          { name: 'data', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'getCreditAccountsByBorrower',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'isSuccessful', internalType: 'bool', type: 'bool' },
          {
            name: 'priceFeedsNeeded',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'borrower', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'cmName', internalType: 'string', type: 'string' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'cumulativeIndexLastUpdate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'cumulativeQuotaInterest',
            internalType: 'uint128',
            type: 'uint128',
          },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'healthFactor', internalType: 'uint256', type: 'uint256' },
          { name: 'baseBorrowRate', internalType: 'uint256', type: 'uint256' },
          {
            name: 'aggregatedBorrowRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'balances',
            internalType: 'struct TokenBalance[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'isForbidden', internalType: 'bool', type: 'bool' },
              { name: 'isEnabled', internalType: 'bool', type: 'bool' },
              { name: 'isQuoted', internalType: 'bool', type: 'bool' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'quotaRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaCumulativeIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
            ],
          },
          { name: 'since', internalType: 'uint64', type: 'uint64' },
          { name: 'cfVersion', internalType: 'uint256', type: 'uint256' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          { name: 'activeBots', internalType: 'address[]', type: 'address[]' },
        ],
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      {
        name: 'priceUpdates',
        internalType: 'struct PriceUpdate[]',
        type: 'tuple[]',
        components: [
          { name: 'priceFeed', internalType: 'address', type: 'address' },
          { name: 'data', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'getCreditAccountsByCreditManager',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'isSuccessful', internalType: 'bool', type: 'bool' },
          {
            name: 'priceFeedsNeeded',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'borrower', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'cmName', internalType: 'string', type: 'string' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'cumulativeIndexLastUpdate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'cumulativeQuotaInterest',
            internalType: 'uint128',
            type: 'uint128',
          },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'healthFactor', internalType: 'uint256', type: 'uint256' },
          { name: 'baseBorrowRate', internalType: 'uint256', type: 'uint256' },
          {
            name: 'aggregatedBorrowRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'balances',
            internalType: 'struct TokenBalance[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'isForbidden', internalType: 'bool', type: 'bool' },
              { name: 'isEnabled', internalType: 'bool', type: 'bool' },
              { name: 'isQuoted', internalType: 'bool', type: 'bool' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'quotaRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaCumulativeIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
            ],
          },
          { name: 'since', internalType: 'uint64', type: 'uint64' },
          { name: 'cfVersion', internalType: 'uint256', type: 'uint256' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          { name: 'activeBots', internalType: 'address[]', type: 'address[]' },
        ],
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'getCreditManagerData',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditManagerData',
        type: 'tuple',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'cfVersion', internalType: 'uint256', type: 'uint256' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          {
            name: 'creditConfigurator',
            internalType: 'address',
            type: 'address',
          },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'pool', internalType: 'address', type: 'address' },
          { name: 'totalDebt', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtLimit', internalType: 'uint256', type: 'uint256' },
          { name: 'baseBorrowRate', internalType: 'uint256', type: 'uint256' },
          { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
          { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'availableToBorrow',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'collateralTokens',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'adapters',
            internalType: 'struct ContractAdapter[]',
            type: 'tuple[]',
            components: [
              {
                name: 'targetContract',
                internalType: 'address',
                type: 'address',
              },
              { name: 'adapter', internalType: 'address', type: 'address' },
            ],
          },
          {
            name: 'liquidationThresholds',
            internalType: 'uint256[]',
            type: 'uint256[]',
          },
          { name: 'isDegenMode', internalType: 'bool', type: 'bool' },
          { name: 'degenNFT', internalType: 'address', type: 'address' },
          {
            name: 'forbiddenTokenMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'maxEnabledTokensLength',
            internalType: 'uint8',
            type: 'uint8',
          },
          { name: 'feeInterest', internalType: 'uint16', type: 'uint16' },
          { name: 'feeLiquidation', internalType: 'uint16', type: 'uint16' },
          {
            name: 'liquidationDiscount',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'feeLiquidationExpired',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'liquidationDiscountExpired',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'quotas',
            internalType: 'struct QuotaInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaIncreaseFee',
                internalType: 'uint16',
                type: 'uint16',
              },
              { name: 'totalQuoted', internalType: 'uint96', type: 'uint96' },
              { name: 'limit', internalType: 'uint96', type: 'uint96' },
              { name: 'isActive', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'lirm',
            internalType: 'struct LinearModel',
            type: 'tuple',
            components: [
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              { name: 'U_1', internalType: 'uint16', type: 'uint16' },
              { name: 'U_2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_base', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope1', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope3', internalType: 'uint16', type: 'uint16' },
              {
                name: 'isBorrowingMoreU2Forbidden',
                internalType: 'bool',
                type: 'bool',
              },
            ],
          },
          { name: 'isPaused', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getCreditManagersV3List',
    outputs: [
      {
        name: '',
        internalType: 'struct CreditManagerData[]',
        type: 'tuple[]',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'cfVersion', internalType: 'uint256', type: 'uint256' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          {
            name: 'creditConfigurator',
            internalType: 'address',
            type: 'address',
          },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'pool', internalType: 'address', type: 'address' },
          { name: 'totalDebt', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtLimit', internalType: 'uint256', type: 'uint256' },
          { name: 'baseBorrowRate', internalType: 'uint256', type: 'uint256' },
          { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
          { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'availableToBorrow',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'collateralTokens',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'adapters',
            internalType: 'struct ContractAdapter[]',
            type: 'tuple[]',
            components: [
              {
                name: 'targetContract',
                internalType: 'address',
                type: 'address',
              },
              { name: 'adapter', internalType: 'address', type: 'address' },
            ],
          },
          {
            name: 'liquidationThresholds',
            internalType: 'uint256[]',
            type: 'uint256[]',
          },
          { name: 'isDegenMode', internalType: 'bool', type: 'bool' },
          { name: 'degenNFT', internalType: 'address', type: 'address' },
          {
            name: 'forbiddenTokenMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'maxEnabledTokensLength',
            internalType: 'uint8',
            type: 'uint8',
          },
          { name: 'feeInterest', internalType: 'uint16', type: 'uint16' },
          { name: 'feeLiquidation', internalType: 'uint16', type: 'uint16' },
          {
            name: 'liquidationDiscount',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'feeLiquidationExpired',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'liquidationDiscountExpired',
            internalType: 'uint16',
            type: 'uint16',
          },
          {
            name: 'quotas',
            internalType: 'struct QuotaInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaIncreaseFee',
                internalType: 'uint16',
                type: 'uint16',
              },
              { name: 'totalQuoted', internalType: 'uint96', type: 'uint96' },
              { name: 'limit', internalType: 'uint96', type: 'uint96' },
              { name: 'isActive', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'lirm',
            internalType: 'struct LinearModel',
            type: 'tuple',
            components: [
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              { name: 'U_1', internalType: 'uint16', type: 'uint16' },
              { name: 'U_2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_base', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope1', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope3', internalType: 'uint16', type: 'uint16' },
              {
                name: 'isBorrowingMoreU2Forbidden',
                internalType: 'bool',
                type: 'bool',
              },
            ],
          },
          { name: 'isPaused', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'staker', internalType: 'address', type: 'address' }],
    name: 'getGaugesV3Data',
    outputs: [
      {
        name: 'result',
        internalType: 'struct GaugeInfo[]',
        type: 'tuple[]',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'pool', internalType: 'address', type: 'address' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'currentEpoch', internalType: 'uint16', type: 'uint16' },
          { name: 'epochFrozen', internalType: 'bool', type: 'bool' },
          {
            name: 'quotaParams',
            internalType: 'struct GaugeQuotaParams[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'minRate', internalType: 'uint16', type: 'uint16' },
              { name: 'maxRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'totalVotesLpSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'totalVotesCaSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaIncreaseFee',
                internalType: 'uint16',
                type: 'uint16',
              },
              { name: 'totalQuoted', internalType: 'uint96', type: 'uint96' },
              { name: 'limit', internalType: 'uint96', type: 'uint96' },
              { name: 'isActive', internalType: 'bool', type: 'bool' },
              {
                name: 'stakerVotesLpSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'stakerVotesCaSide',
                internalType: 'uint96',
                type: 'uint96',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'priceUpdates',
        internalType: 'struct PriceUpdate[]',
        type: 'tuple[]',
        components: [
          { name: 'priceFeed', internalType: 'address', type: 'address' },
          { name: 'data', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'getLiquidatableCreditAccounts',
    outputs: [
      {
        name: 'result',
        internalType: 'struct CreditAccountData[]',
        type: 'tuple[]',
        components: [
          { name: 'isSuccessful', internalType: 'bool', type: 'bool' },
          {
            name: 'priceFeedsNeeded',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'borrower', internalType: 'address', type: 'address' },
          { name: 'creditManager', internalType: 'address', type: 'address' },
          { name: 'cmName', internalType: 'string', type: 'string' },
          { name: 'creditFacade', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'debt', internalType: 'uint256', type: 'uint256' },
          {
            name: 'cumulativeIndexLastUpdate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'cumulativeQuotaInterest',
            internalType: 'uint128',
            type: 'uint128',
          },
          { name: 'accruedInterest', internalType: 'uint256', type: 'uint256' },
          { name: 'accruedFees', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValue', internalType: 'uint256', type: 'uint256' },
          { name: 'totalValueUSD', internalType: 'uint256', type: 'uint256' },
          { name: 'twvUSD', internalType: 'uint256', type: 'uint256' },
          {
            name: 'enabledTokensMask',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'healthFactor', internalType: 'uint256', type: 'uint256' },
          { name: 'baseBorrowRate', internalType: 'uint256', type: 'uint256' },
          {
            name: 'aggregatedBorrowRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'balances',
            internalType: 'struct TokenBalance[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'balance', internalType: 'uint256', type: 'uint256' },
              { name: 'isForbidden', internalType: 'bool', type: 'bool' },
              { name: 'isEnabled', internalType: 'bool', type: 'bool' },
              { name: 'isQuoted', internalType: 'bool', type: 'bool' },
              { name: 'quota', internalType: 'uint256', type: 'uint256' },
              { name: 'quotaRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaCumulativeIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
            ],
          },
          { name: 'since', internalType: 'uint64', type: 'uint64' },
          { name: 'cfVersion', internalType: 'uint256', type: 'uint256' },
          { name: 'expirationDate', internalType: 'uint40', type: 'uint40' },
          { name: 'activeBots', internalType: 'address[]', type: 'address[]' },
        ],
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: '_pool', internalType: 'address', type: 'address' }],
    name: 'getPoolData',
    outputs: [
      {
        name: '',
        internalType: 'struct PoolData',
        type: 'tuple',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'dieselToken', internalType: 'address', type: 'address' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          {
            name: 'baseInterestIndex',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'availableLiquidity',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'expectedLiquidity',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'totalBorrowed', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtLimit', internalType: 'uint256', type: 'uint256' },
          {
            name: 'creditManagerDebtParams',
            internalType: 'struct CreditManagerDebtParams[]',
            type: 'tuple[]',
            components: [
              {
                name: 'creditManager',
                internalType: 'address',
                type: 'address',
              },
              { name: 'borrowed', internalType: 'uint256', type: 'uint256' },
              { name: 'limit', internalType: 'uint256', type: 'uint256' },
              {
                name: 'availableToBorrow',
                internalType: 'uint256',
                type: 'uint256',
              },
            ],
          },
          { name: 'totalAssets', internalType: 'uint256', type: 'uint256' },
          { name: 'totalSupply', internalType: 'uint256', type: 'uint256' },
          { name: 'supplyRate', internalType: 'uint256', type: 'uint256' },
          {
            name: 'baseInterestRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'dieselRate_RAY', internalType: 'uint256', type: 'uint256' },
          { name: 'withdrawFee', internalType: 'uint256', type: 'uint256' },
          {
            name: 'lastBaseInterestUpdate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'baseInterestIndexLU',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'version', internalType: 'uint256', type: 'uint256' },
          { name: 'poolQuotaKeeper', internalType: 'address', type: 'address' },
          { name: 'gauge', internalType: 'address', type: 'address' },
          {
            name: 'quotas',
            internalType: 'struct QuotaInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaIncreaseFee',
                internalType: 'uint16',
                type: 'uint16',
              },
              { name: 'totalQuoted', internalType: 'uint96', type: 'uint96' },
              { name: 'limit', internalType: 'uint96', type: 'uint96' },
              { name: 'isActive', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'zappers',
            internalType: 'struct ZapperInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'zapper', internalType: 'address', type: 'address' },
              { name: 'tokenIn', internalType: 'address', type: 'address' },
              { name: 'tokenOut', internalType: 'address', type: 'address' },
            ],
          },
          {
            name: 'lirm',
            internalType: 'struct LinearModel',
            type: 'tuple',
            components: [
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              { name: 'U_1', internalType: 'uint16', type: 'uint16' },
              { name: 'U_2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_base', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope1', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope3', internalType: 'uint16', type: 'uint16' },
              {
                name: 'isBorrowingMoreU2Forbidden',
                internalType: 'bool',
                type: 'bool',
              },
            ],
          },
          { name: 'isPaused', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'getPoolsV3List',
    outputs: [
      {
        name: '',
        internalType: 'struct PoolData[]',
        type: 'tuple[]',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'dieselToken', internalType: 'address', type: 'address' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          {
            name: 'baseInterestIndex',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'availableLiquidity',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'expectedLiquidity',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'totalBorrowed', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtLimit', internalType: 'uint256', type: 'uint256' },
          {
            name: 'creditManagerDebtParams',
            internalType: 'struct CreditManagerDebtParams[]',
            type: 'tuple[]',
            components: [
              {
                name: 'creditManager',
                internalType: 'address',
                type: 'address',
              },
              { name: 'borrowed', internalType: 'uint256', type: 'uint256' },
              { name: 'limit', internalType: 'uint256', type: 'uint256' },
              {
                name: 'availableToBorrow',
                internalType: 'uint256',
                type: 'uint256',
              },
            ],
          },
          { name: 'totalAssets', internalType: 'uint256', type: 'uint256' },
          { name: 'totalSupply', internalType: 'uint256', type: 'uint256' },
          { name: 'supplyRate', internalType: 'uint256', type: 'uint256' },
          {
            name: 'baseInterestRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'dieselRate_RAY', internalType: 'uint256', type: 'uint256' },
          { name: 'withdrawFee', internalType: 'uint256', type: 'uint256' },
          {
            name: 'lastBaseInterestUpdate',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'baseInterestIndexLU',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'version', internalType: 'uint256', type: 'uint256' },
          { name: 'poolQuotaKeeper', internalType: 'address', type: 'address' },
          { name: 'gauge', internalType: 'address', type: 'address' },
          {
            name: 'quotas',
            internalType: 'struct QuotaInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'quotaIncreaseFee',
                internalType: 'uint16',
                type: 'uint16',
              },
              { name: 'totalQuoted', internalType: 'uint96', type: 'uint96' },
              { name: 'limit', internalType: 'uint96', type: 'uint96' },
              { name: 'isActive', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'zappers',
            internalType: 'struct ZapperInfo[]',
            type: 'tuple[]',
            components: [
              { name: 'zapper', internalType: 'address', type: 'address' },
              { name: 'tokenIn', internalType: 'address', type: 'address' },
              { name: 'tokenOut', internalType: 'address', type: 'address' },
            ],
          },
          {
            name: 'lirm',
            internalType: 'struct LinearModel',
            type: 'tuple',
            components: [
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              { name: 'U_1', internalType: 'uint16', type: 'uint16' },
              { name: 'U_2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_base', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope1', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope2', internalType: 'uint16', type: 'uint16' },
              { name: 'R_slope3', internalType: 'uint16', type: 'uint16' },
              {
                name: 'isBorrowingMoreU2Forbidden',
                internalType: 'bool',
                type: 'bool',
              },
            ],
          },
          { name: 'isPaused', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IGaugeCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iGaugeCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'gauge', internalType: 'address', type: 'address' },
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'getGauge',
    outputs: [
      {
        name: 'result',
        internalType: 'struct GaugeInfo',
        type: 'tuple',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'pool', internalType: 'address', type: 'address' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'voter', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'currentEpoch', internalType: 'uint16', type: 'uint16' },
          { name: 'epochLastUpdate', internalType: 'uint16', type: 'uint16' },
          { name: 'epochFrozen', internalType: 'bool', type: 'bool' },
          {
            name: 'quotaParams',
            internalType: 'struct GaugeQuotaParams[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'minRate', internalType: 'uint16', type: 'uint16' },
              { name: 'maxRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'totalVotesLpSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'totalVotesCaSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'stakerVotesLpSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'stakerVotesCaSide',
                internalType: 'uint96',
                type: 'uint96',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'filter',
        internalType: 'struct MarketFilter',
        type: 'tuple',
        components: [
          {
            name: 'configurators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'pools', internalType: 'address[]', type: 'address[]' },
          { name: 'underlying', internalType: 'address', type: 'address' },
        ],
      },
      { name: 'staker', internalType: 'address', type: 'address' },
    ],
    name: 'getGauges',
    outputs: [
      {
        name: 'result',
        internalType: 'struct GaugeInfo[]',
        type: 'tuple[]',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'pool', internalType: 'address', type: 'address' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'voter', internalType: 'address', type: 'address' },
          { name: 'underlying', internalType: 'address', type: 'address' },
          { name: 'currentEpoch', internalType: 'uint16', type: 'uint16' },
          { name: 'epochLastUpdate', internalType: 'uint16', type: 'uint16' },
          { name: 'epochFrozen', internalType: 'bool', type: 'bool' },
          {
            name: 'quotaParams',
            internalType: 'struct GaugeQuotaParams[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'minRate', internalType: 'uint16', type: 'uint16' },
              { name: 'maxRate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'totalVotesLpSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'totalVotesCaSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'stakerVotesLpSide',
                internalType: 'uint96',
                type: 'uint96',
              },
              {
                name: 'stakerVotesCaSide',
                internalType: 'uint96',
                type: 'uint96',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IMarketCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iMarketCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'configurator', internalType: 'address', type: 'address' },
    ],
    name: 'getMarketData',
    outputs: [
      {
        name: 'result',
        internalType: 'struct MarketData',
        type: 'tuple',
        components: [
          { name: 'acl', internalType: 'address', type: 'address' },
          {
            name: 'contractsRegister',
            internalType: 'address',
            type: 'address',
          },
          { name: 'treasury', internalType: 'address', type: 'address' },
          {
            name: 'pool',
            internalType: 'struct PoolState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
              { name: 'totalSupply', internalType: 'uint256', type: 'uint256' },
              {
                name: 'poolQuotaKeeper',
                internalType: 'address',
                type: 'address',
              },
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'underlying', internalType: 'address', type: 'address' },
              {
                name: 'availableLiquidity',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'expectedLiquidity',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'baseInterestIndex',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'baseInterestRate',
                internalType: 'uint256',
                type: 'uint256',
              },
              { name: 'dieselRate', internalType: 'uint256', type: 'uint256' },
              { name: 'supplyRate', internalType: 'uint256', type: 'uint256' },
              { name: 'withdrawFee', internalType: 'uint256', type: 'uint256' },
              {
                name: 'totalBorrowed',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'totalDebtLimit',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'creditManagerDebtParams',
                internalType: 'struct CreditManagerDebtParams[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'creditManager',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'borrowed',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                  { name: 'limit', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'available',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                ],
              },
              {
                name: 'baseInterestIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'expectedLiquidityLU',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'quotaRevenue',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'lastBaseInterestUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
              {
                name: 'lastQuotaRevenueUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
              { name: 'isPaused', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'poolQuotaKeeper',
            internalType: 'struct PoolQuotaKeeperState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'rateKeeper', internalType: 'address', type: 'address' },
              {
                name: 'quotas',
                internalType: 'struct QuotaTokenParams[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'rate', internalType: 'uint16', type: 'uint16' },
                  {
                    name: 'cumulativeIndexLU',
                    internalType: 'uint192',
                    type: 'uint192',
                  },
                  {
                    name: 'quotaIncreaseFee',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'totalQuoted',
                    internalType: 'uint96',
                    type: 'uint96',
                  },
                  { name: 'limit', internalType: 'uint96', type: 'uint96' },
                  { name: 'isActive', internalType: 'bool', type: 'bool' },
                ],
              },
              {
                name: 'creditManagers',
                internalType: 'address[]',
                type: 'address[]',
              },
              {
                name: 'lastQuotaRateUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
            ],
          },
          {
            name: 'interestRateModel',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'rateKeeper',
            internalType: 'struct RateKeeperState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'rates',
                internalType: 'struct Rate[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'rate', internalType: 'uint16', type: 'uint16' },
                ],
              },
            ],
          },
          {
            name: 'priceOracleData',
            internalType: 'struct PriceOracleState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'priceFeedMapping',
                internalType: 'struct PriceFeedMapEntry[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'reserve', internalType: 'bool', type: 'bool' },
                  {
                    name: 'priceFeed',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'stalenessPeriod',
                    internalType: 'uint32',
                    type: 'uint32',
                  },
                ],
              },
              {
                name: 'priceFeedStructure',
                internalType: 'struct PriceFeedTreeNode[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'description',
                    internalType: 'string',
                    type: 'string',
                  },
                  { name: 'decimals', internalType: 'uint8', type: 'uint8' },
                  { name: 'skipCheck', internalType: 'bool', type: 'bool' },
                  { name: 'updatable', internalType: 'bool', type: 'bool' },
                  {
                    name: 'underlyingFeeds',
                    internalType: 'address[]',
                    type: 'address[]',
                  },
                  {
                    name: 'underlyingStalenessPeriods',
                    internalType: 'uint32[]',
                    type: 'uint32[]',
                  },
                  {
                    name: 'answer',
                    internalType: 'struct PriceFeedAnswer',
                    type: 'tuple',
                    components: [
                      { name: 'price', internalType: 'int256', type: 'int256' },
                      {
                        name: 'updatedAt',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      { name: 'success', internalType: 'bool', type: 'bool' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            name: 'lossPolicy',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'tokens',
            internalType: 'struct TokenData[]',
            type: 'tuple[]',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
            ],
          },
          {
            name: 'creditManagers',
            internalType: 'struct CreditSuiteData[]',
            type: 'tuple[]',
            components: [
              {
                name: 'creditFacade',
                internalType: 'struct CreditFacadeState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'creditManager',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'degenNFT',
                    internalType: 'address',
                    type: 'address',
                  },
                  { name: 'botList', internalType: 'address', type: 'address' },
                  { name: 'expirable', internalType: 'bool', type: 'bool' },
                  {
                    name: 'expirationDate',
                    internalType: 'uint40',
                    type: 'uint40',
                  },
                  {
                    name: 'maxDebtPerBlockMultiplier',
                    internalType: 'uint8',
                    type: 'uint8',
                  },
                  { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
                  { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'forbiddenTokenMask',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                  { name: 'isPaused', internalType: 'bool', type: 'bool' },
                ],
              },
              {
                name: 'creditManager',
                internalType: 'struct CreditManagerState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  { name: 'name', internalType: 'string', type: 'string' },
                  {
                    name: 'accountFactory',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'underlying',
                    internalType: 'address',
                    type: 'address',
                  },
                  { name: 'pool', internalType: 'address', type: 'address' },
                  {
                    name: 'creditFacade',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'creditConfigurator',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'maxEnabledTokens',
                    internalType: 'uint8',
                    type: 'uint8',
                  },
                  {
                    name: 'collateralTokens',
                    internalType: 'struct CollateralToken[]',
                    type: 'tuple[]',
                    components: [
                      {
                        name: 'token',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'liquidationThreshold',
                        internalType: 'uint16',
                        type: 'uint16',
                      },
                    ],
                  },
                  {
                    name: 'feeInterest',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'feeLiquidation',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'liquidationDiscount',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'feeLiquidationExpired',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'liquidationDiscountExpired',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                ],
              },
              {
                name: 'creditConfigurator',
                internalType: 'struct BaseState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                ],
              },
              {
                name: 'adapters',
                internalType: 'struct AdapterState[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'targetContract',
                    internalType: 'address',
                    type: 'address',
                  },
                ],
              },
            ],
          },
          { name: 'configurator', internalType: 'address', type: 'address' },
          {
            name: 'pausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'unpausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'emergencyLiquidators',
            internalType: 'address[]',
            type: 'address[]',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'getMarketData',
    outputs: [
      {
        name: 'result',
        internalType: 'struct MarketData',
        type: 'tuple',
        components: [
          { name: 'acl', internalType: 'address', type: 'address' },
          {
            name: 'contractsRegister',
            internalType: 'address',
            type: 'address',
          },
          { name: 'treasury', internalType: 'address', type: 'address' },
          {
            name: 'pool',
            internalType: 'struct PoolState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
              { name: 'totalSupply', internalType: 'uint256', type: 'uint256' },
              {
                name: 'poolQuotaKeeper',
                internalType: 'address',
                type: 'address',
              },
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'underlying', internalType: 'address', type: 'address' },
              {
                name: 'availableLiquidity',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'expectedLiquidity',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'baseInterestIndex',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'baseInterestRate',
                internalType: 'uint256',
                type: 'uint256',
              },
              { name: 'dieselRate', internalType: 'uint256', type: 'uint256' },
              { name: 'supplyRate', internalType: 'uint256', type: 'uint256' },
              { name: 'withdrawFee', internalType: 'uint256', type: 'uint256' },
              {
                name: 'totalBorrowed',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'totalDebtLimit',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'creditManagerDebtParams',
                internalType: 'struct CreditManagerDebtParams[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'creditManager',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'borrowed',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                  { name: 'limit', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'available',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                ],
              },
              {
                name: 'baseInterestIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'expectedLiquidityLU',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'quotaRevenue',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'lastBaseInterestUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
              {
                name: 'lastQuotaRevenueUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
              { name: 'isPaused', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'poolQuotaKeeper',
            internalType: 'struct PoolQuotaKeeperState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'rateKeeper', internalType: 'address', type: 'address' },
              {
                name: 'quotas',
                internalType: 'struct QuotaTokenParams[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'rate', internalType: 'uint16', type: 'uint16' },
                  {
                    name: 'cumulativeIndexLU',
                    internalType: 'uint192',
                    type: 'uint192',
                  },
                  {
                    name: 'quotaIncreaseFee',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'totalQuoted',
                    internalType: 'uint96',
                    type: 'uint96',
                  },
                  { name: 'limit', internalType: 'uint96', type: 'uint96' },
                  { name: 'isActive', internalType: 'bool', type: 'bool' },
                ],
              },
              {
                name: 'creditManagers',
                internalType: 'address[]',
                type: 'address[]',
              },
              {
                name: 'lastQuotaRateUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
            ],
          },
          {
            name: 'interestRateModel',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'rateKeeper',
            internalType: 'struct RateKeeperState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'rates',
                internalType: 'struct Rate[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'rate', internalType: 'uint16', type: 'uint16' },
                ],
              },
            ],
          },
          {
            name: 'priceOracleData',
            internalType: 'struct PriceOracleState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'priceFeedMapping',
                internalType: 'struct PriceFeedMapEntry[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'reserve', internalType: 'bool', type: 'bool' },
                  {
                    name: 'priceFeed',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'stalenessPeriod',
                    internalType: 'uint32',
                    type: 'uint32',
                  },
                ],
              },
              {
                name: 'priceFeedStructure',
                internalType: 'struct PriceFeedTreeNode[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'description',
                    internalType: 'string',
                    type: 'string',
                  },
                  { name: 'decimals', internalType: 'uint8', type: 'uint8' },
                  { name: 'skipCheck', internalType: 'bool', type: 'bool' },
                  { name: 'updatable', internalType: 'bool', type: 'bool' },
                  {
                    name: 'underlyingFeeds',
                    internalType: 'address[]',
                    type: 'address[]',
                  },
                  {
                    name: 'underlyingStalenessPeriods',
                    internalType: 'uint32[]',
                    type: 'uint32[]',
                  },
                  {
                    name: 'answer',
                    internalType: 'struct PriceFeedAnswer',
                    type: 'tuple',
                    components: [
                      { name: 'price', internalType: 'int256', type: 'int256' },
                      {
                        name: 'updatedAt',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      { name: 'success', internalType: 'bool', type: 'bool' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            name: 'lossPolicy',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'tokens',
            internalType: 'struct TokenData[]',
            type: 'tuple[]',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
            ],
          },
          {
            name: 'creditManagers',
            internalType: 'struct CreditSuiteData[]',
            type: 'tuple[]',
            components: [
              {
                name: 'creditFacade',
                internalType: 'struct CreditFacadeState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'creditManager',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'degenNFT',
                    internalType: 'address',
                    type: 'address',
                  },
                  { name: 'botList', internalType: 'address', type: 'address' },
                  { name: 'expirable', internalType: 'bool', type: 'bool' },
                  {
                    name: 'expirationDate',
                    internalType: 'uint40',
                    type: 'uint40',
                  },
                  {
                    name: 'maxDebtPerBlockMultiplier',
                    internalType: 'uint8',
                    type: 'uint8',
                  },
                  { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
                  { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'forbiddenTokenMask',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                  { name: 'isPaused', internalType: 'bool', type: 'bool' },
                ],
              },
              {
                name: 'creditManager',
                internalType: 'struct CreditManagerState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  { name: 'name', internalType: 'string', type: 'string' },
                  {
                    name: 'accountFactory',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'underlying',
                    internalType: 'address',
                    type: 'address',
                  },
                  { name: 'pool', internalType: 'address', type: 'address' },
                  {
                    name: 'creditFacade',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'creditConfigurator',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'maxEnabledTokens',
                    internalType: 'uint8',
                    type: 'uint8',
                  },
                  {
                    name: 'collateralTokens',
                    internalType: 'struct CollateralToken[]',
                    type: 'tuple[]',
                    components: [
                      {
                        name: 'token',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'liquidationThreshold',
                        internalType: 'uint16',
                        type: 'uint16',
                      },
                    ],
                  },
                  {
                    name: 'feeInterest',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'feeLiquidation',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'liquidationDiscount',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'feeLiquidationExpired',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'liquidationDiscountExpired',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                ],
              },
              {
                name: 'creditConfigurator',
                internalType: 'struct BaseState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                ],
              },
              {
                name: 'adapters',
                internalType: 'struct AdapterState[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'targetContract',
                    internalType: 'address',
                    type: 'address',
                  },
                ],
              },
            ],
          },
          { name: 'configurator', internalType: 'address', type: 'address' },
          {
            name: 'pausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'unpausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'emergencyLiquidators',
            internalType: 'address[]',
            type: 'address[]',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'filter',
        internalType: 'struct MarketFilter',
        type: 'tuple',
        components: [
          {
            name: 'configurators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'pools', internalType: 'address[]', type: 'address[]' },
          { name: 'underlying', internalType: 'address', type: 'address' },
        ],
      },
    ],
    name: 'getMarkets',
    outputs: [
      {
        name: 'result',
        internalType: 'struct MarketData[]',
        type: 'tuple[]',
        components: [
          { name: 'acl', internalType: 'address', type: 'address' },
          {
            name: 'contractsRegister',
            internalType: 'address',
            type: 'address',
          },
          { name: 'treasury', internalType: 'address', type: 'address' },
          {
            name: 'pool',
            internalType: 'struct PoolState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
              { name: 'totalSupply', internalType: 'uint256', type: 'uint256' },
              {
                name: 'poolQuotaKeeper',
                internalType: 'address',
                type: 'address',
              },
              {
                name: 'interestRateModel',
                internalType: 'address',
                type: 'address',
              },
              { name: 'underlying', internalType: 'address', type: 'address' },
              {
                name: 'availableLiquidity',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'expectedLiquidity',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'baseInterestIndex',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'baseInterestRate',
                internalType: 'uint256',
                type: 'uint256',
              },
              { name: 'dieselRate', internalType: 'uint256', type: 'uint256' },
              { name: 'supplyRate', internalType: 'uint256', type: 'uint256' },
              { name: 'withdrawFee', internalType: 'uint256', type: 'uint256' },
              {
                name: 'totalBorrowed',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'totalDebtLimit',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'creditManagerDebtParams',
                internalType: 'struct CreditManagerDebtParams[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'creditManager',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'borrowed',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                  { name: 'limit', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'available',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                ],
              },
              {
                name: 'baseInterestIndexLU',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'expectedLiquidityLU',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'quotaRevenue',
                internalType: 'uint256',
                type: 'uint256',
              },
              {
                name: 'lastBaseInterestUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
              {
                name: 'lastQuotaRevenueUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
              { name: 'isPaused', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'poolQuotaKeeper',
            internalType: 'struct PoolQuotaKeeperState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              { name: 'rateKeeper', internalType: 'address', type: 'address' },
              {
                name: 'quotas',
                internalType: 'struct QuotaTokenParams[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'rate', internalType: 'uint16', type: 'uint16' },
                  {
                    name: 'cumulativeIndexLU',
                    internalType: 'uint192',
                    type: 'uint192',
                  },
                  {
                    name: 'quotaIncreaseFee',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'totalQuoted',
                    internalType: 'uint96',
                    type: 'uint96',
                  },
                  { name: 'limit', internalType: 'uint96', type: 'uint96' },
                  { name: 'isActive', internalType: 'bool', type: 'bool' },
                ],
              },
              {
                name: 'creditManagers',
                internalType: 'address[]',
                type: 'address[]',
              },
              {
                name: 'lastQuotaRateUpdate',
                internalType: 'uint40',
                type: 'uint40',
              },
            ],
          },
          {
            name: 'interestRateModel',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'rateKeeper',
            internalType: 'struct RateKeeperState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'rates',
                internalType: 'struct Rate[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'rate', internalType: 'uint16', type: 'uint16' },
                ],
              },
            ],
          },
          {
            name: 'priceOracleData',
            internalType: 'struct PriceOracleState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
              {
                name: 'priceFeedMapping',
                internalType: 'struct PriceFeedMapEntry[]',
                type: 'tuple[]',
                components: [
                  { name: 'token', internalType: 'address', type: 'address' },
                  { name: 'reserve', internalType: 'bool', type: 'bool' },
                  {
                    name: 'priceFeed',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'stalenessPeriod',
                    internalType: 'uint32',
                    type: 'uint32',
                  },
                ],
              },
              {
                name: 'priceFeedStructure',
                internalType: 'struct PriceFeedTreeNode[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'description',
                    internalType: 'string',
                    type: 'string',
                  },
                  { name: 'decimals', internalType: 'uint8', type: 'uint8' },
                  { name: 'skipCheck', internalType: 'bool', type: 'bool' },
                  { name: 'updatable', internalType: 'bool', type: 'bool' },
                  {
                    name: 'underlyingFeeds',
                    internalType: 'address[]',
                    type: 'address[]',
                  },
                  {
                    name: 'underlyingStalenessPeriods',
                    internalType: 'uint32[]',
                    type: 'uint32[]',
                  },
                  {
                    name: 'answer',
                    internalType: 'struct PriceFeedAnswer',
                    type: 'tuple',
                    components: [
                      { name: 'price', internalType: 'int256', type: 'int256' },
                      {
                        name: 'updatedAt',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      { name: 'success', internalType: 'bool', type: 'bool' },
                    ],
                  },
                ],
              },
            ],
          },
          {
            name: 'lossPolicy',
            internalType: 'struct BaseState',
            type: 'tuple',
            components: [
              {
                name: 'baseParams',
                internalType: 'struct BaseParams',
                type: 'tuple',
                components: [
                  { name: 'addr', internalType: 'address', type: 'address' },
                  { name: 'version', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'contractType',
                    internalType: 'bytes32',
                    type: 'bytes32',
                  },
                  {
                    name: 'serializedParams',
                    internalType: 'bytes',
                    type: 'bytes',
                  },
                ],
              },
            ],
          },
          {
            name: 'tokens',
            internalType: 'struct TokenData[]',
            type: 'tuple[]',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
            ],
          },
          {
            name: 'creditManagers',
            internalType: 'struct CreditSuiteData[]',
            type: 'tuple[]',
            components: [
              {
                name: 'creditFacade',
                internalType: 'struct CreditFacadeState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'creditManager',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'degenNFT',
                    internalType: 'address',
                    type: 'address',
                  },
                  { name: 'botList', internalType: 'address', type: 'address' },
                  { name: 'expirable', internalType: 'bool', type: 'bool' },
                  {
                    name: 'expirationDate',
                    internalType: 'uint40',
                    type: 'uint40',
                  },
                  {
                    name: 'maxDebtPerBlockMultiplier',
                    internalType: 'uint8',
                    type: 'uint8',
                  },
                  { name: 'minDebt', internalType: 'uint256', type: 'uint256' },
                  { name: 'maxDebt', internalType: 'uint256', type: 'uint256' },
                  {
                    name: 'forbiddenTokenMask',
                    internalType: 'uint256',
                    type: 'uint256',
                  },
                  { name: 'isPaused', internalType: 'bool', type: 'bool' },
                ],
              },
              {
                name: 'creditManager',
                internalType: 'struct CreditManagerState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  { name: 'name', internalType: 'string', type: 'string' },
                  {
                    name: 'accountFactory',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'underlying',
                    internalType: 'address',
                    type: 'address',
                  },
                  { name: 'pool', internalType: 'address', type: 'address' },
                  {
                    name: 'creditFacade',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'creditConfigurator',
                    internalType: 'address',
                    type: 'address',
                  },
                  {
                    name: 'maxEnabledTokens',
                    internalType: 'uint8',
                    type: 'uint8',
                  },
                  {
                    name: 'collateralTokens',
                    internalType: 'struct CollateralToken[]',
                    type: 'tuple[]',
                    components: [
                      {
                        name: 'token',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'liquidationThreshold',
                        internalType: 'uint16',
                        type: 'uint16',
                      },
                    ],
                  },
                  {
                    name: 'feeInterest',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'feeLiquidation',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'liquidationDiscount',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'feeLiquidationExpired',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                  {
                    name: 'liquidationDiscountExpired',
                    internalType: 'uint16',
                    type: 'uint16',
                  },
                ],
              },
              {
                name: 'creditConfigurator',
                internalType: 'struct BaseState',
                type: 'tuple',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                ],
              },
              {
                name: 'adapters',
                internalType: 'struct AdapterState[]',
                type: 'tuple[]',
                components: [
                  {
                    name: 'baseParams',
                    internalType: 'struct BaseParams',
                    type: 'tuple',
                    components: [
                      {
                        name: 'addr',
                        internalType: 'address',
                        type: 'address',
                      },
                      {
                        name: 'version',
                        internalType: 'uint256',
                        type: 'uint256',
                      },
                      {
                        name: 'contractType',
                        internalType: 'bytes32',
                        type: 'bytes32',
                      },
                      {
                        name: 'serializedParams',
                        internalType: 'bytes',
                        type: 'bytes',
                      },
                    ],
                  },
                  {
                    name: 'targetContract',
                    internalType: 'address',
                    type: 'address',
                  },
                ],
              },
            ],
          },
          { name: 'configurator', internalType: 'address', type: 'address' },
          {
            name: 'pausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'unpausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'emergencyLiquidators',
            internalType: 'address[]',
            type: 'address[]',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      {
        name: 'filter',
        internalType: 'struct MarketFilter',
        type: 'tuple',
        components: [
          {
            name: 'configurators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'pools', internalType: 'address[]', type: 'address[]' },
          { name: 'underlying', internalType: 'address', type: 'address' },
        ],
      },
    ],
    name: 'getUpdatablePriceFeeds',
    outputs: [
      {
        name: 'updatablePriceFeeds',
        internalType: 'struct BaseParams[]',
        type: 'tuple[]',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'version', internalType: 'uint256', type: 'uint256' },
          { name: 'contractType', internalType: 'bytes32', type: 'bytes32' },
          { name: 'serializedParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IModifiedBooster
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iModifiedBoosterAbi = [
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'getRewardMultipliers',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IPeripheryCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iPeripheryCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'marketConfigurator', internalType: 'address', type: 'address' },
      { name: 'creditAccount', internalType: 'address', type: 'address' },
    ],
    name: 'getActiveBots',
    outputs: [
      {
        name: '',
        internalType: 'struct BotState[]',
        type: 'tuple[]',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'permissions', internalType: 'uint192', type: 'uint192' },
          { name: 'forbidden', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'marketConfigurator', internalType: 'address', type: 'address' },
      { name: 'pool', internalType: 'address', type: 'address' },
    ],
    name: 'getZappers',
    outputs: [
      {
        name: '',
        internalType: 'struct ZapperState[]',
        type: 'tuple[]',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          {
            name: 'tokenIn',
            internalType: 'struct TokenData',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
            ],
          },
          {
            name: 'tokenOut',
            internalType: 'struct TokenData',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'symbol', internalType: 'string', type: 'string' },
              { name: 'name', internalType: 'string', type: 'string' },
              { name: 'decimals', internalType: 'uint8', type: 'uint8' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IPoolCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iPoolCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'interestRateModel', internalType: 'address', type: 'address' },
    ],
    name: 'getInterestRateModelState',
    outputs: [
      {
        name: '',
        internalType: 'struct BaseState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'lossPolicy', internalType: 'address', type: 'address' }],
    name: 'getLossPolicyState',
    outputs: [
      {
        name: '',
        internalType: 'struct BaseState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'quotaKeeper', internalType: 'address', type: 'address' }],
    name: 'getPoolQuotaKeeperState',
    outputs: [
      {
        name: '',
        internalType: 'struct PoolQuotaKeeperState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'rateKeeper', internalType: 'address', type: 'address' },
          {
            name: 'quotas',
            internalType: 'struct QuotaTokenParams[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
              {
                name: 'cumulativeIndexLU',
                internalType: 'uint192',
                type: 'uint192',
              },
              {
                name: 'quotaIncreaseFee',
                internalType: 'uint16',
                type: 'uint16',
              },
              { name: 'totalQuoted', internalType: 'uint96', type: 'uint96' },
              { name: 'limit', internalType: 'uint96', type: 'uint96' },
              { name: 'isActive', internalType: 'bool', type: 'bool' },
            ],
          },
          {
            name: 'creditManagers',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'lastQuotaRateUpdate',
            internalType: 'uint40',
            type: 'uint40',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'getPoolState',
    outputs: [
      {
        name: '',
        internalType: 'struct PoolState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'decimals', internalType: 'uint8', type: 'uint8' },
          { name: 'totalSupply', internalType: 'uint256', type: 'uint256' },
          { name: 'poolQuotaKeeper', internalType: 'address', type: 'address' },
          {
            name: 'interestRateModel',
            internalType: 'address',
            type: 'address',
          },
          { name: 'underlying', internalType: 'address', type: 'address' },
          {
            name: 'availableLiquidity',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'expectedLiquidity',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'baseInterestIndex',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'baseInterestRate',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'dieselRate', internalType: 'uint256', type: 'uint256' },
          { name: 'supplyRate', internalType: 'uint256', type: 'uint256' },
          { name: 'withdrawFee', internalType: 'uint256', type: 'uint256' },
          { name: 'totalBorrowed', internalType: 'uint256', type: 'uint256' },
          { name: 'totalDebtLimit', internalType: 'uint256', type: 'uint256' },
          {
            name: 'creditManagerDebtParams',
            internalType: 'struct CreditManagerDebtParams[]',
            type: 'tuple[]',
            components: [
              {
                name: 'creditManager',
                internalType: 'address',
                type: 'address',
              },
              { name: 'borrowed', internalType: 'uint256', type: 'uint256' },
              { name: 'limit', internalType: 'uint256', type: 'uint256' },
              { name: 'available', internalType: 'uint256', type: 'uint256' },
            ],
          },
          {
            name: 'baseInterestIndexLU',
            internalType: 'uint256',
            type: 'uint256',
          },
          {
            name: 'expectedLiquidityLU',
            internalType: 'uint256',
            type: 'uint256',
          },
          { name: 'quotaRevenue', internalType: 'uint256', type: 'uint256' },
          {
            name: 'lastBaseInterestUpdate',
            internalType: 'uint40',
            type: 'uint40',
          },
          {
            name: 'lastQuotaRevenueUpdate',
            internalType: 'uint40',
            type: 'uint40',
          },
          { name: 'isPaused', internalType: 'bool', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'rateKeeper', internalType: 'address', type: 'address' }],
    name: 'getRateKeeperState',
    outputs: [
      {
        name: '',
        internalType: 'struct RateKeeperState',
        type: 'tuple',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          {
            name: 'rates',
            internalType: 'struct Rate[]',
            type: 'tuple[]',
            components: [
              { name: 'token', internalType: 'address', type: 'address' },
              { name: 'rate', internalType: 'uint16', type: 'uint16' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IPriceFeedCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iPriceFeedCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'priceOracle', internalType: 'address', type: 'address' },
      { name: 'tokens', internalType: 'address[]', type: 'address[]' },
    ],
    name: 'getPriceFeeds',
    outputs: [
      {
        name: 'priceFeedMap',
        internalType: 'struct PriceFeedMapEntry[]',
        type: 'tuple[]',
        components: [
          { name: 'token', internalType: 'address', type: 'address' },
          { name: 'reserve', internalType: 'bool', type: 'bool' },
          { name: 'priceFeed', internalType: 'address', type: 'address' },
          { name: 'stalenessPeriod', internalType: 'uint32', type: 'uint32' },
        ],
      },
      {
        name: 'priceFeedTree',
        internalType: 'struct PriceFeedTreeNode[]',
        type: 'tuple[]',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'description', internalType: 'string', type: 'string' },
          { name: 'decimals', internalType: 'uint8', type: 'uint8' },
          { name: 'skipCheck', internalType: 'bool', type: 'bool' },
          { name: 'updatable', internalType: 'bool', type: 'bool' },
          {
            name: 'underlyingFeeds',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'underlyingStalenessPeriods',
            internalType: 'uint32[]',
            type: 'uint32[]',
          },
          {
            name: 'answer',
            internalType: 'struct PriceFeedAnswer',
            type: 'tuple',
            components: [
              { name: 'price', internalType: 'int256', type: 'int256' },
              { name: 'updatedAt', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'priceOracle', internalType: 'address', type: 'address' }],
    name: 'getPriceFeeds',
    outputs: [
      {
        name: 'priceFeedMap',
        internalType: 'struct PriceFeedMapEntry[]',
        type: 'tuple[]',
        components: [
          { name: 'token', internalType: 'address', type: 'address' },
          { name: 'reserve', internalType: 'bool', type: 'bool' },
          { name: 'priceFeed', internalType: 'address', type: 'address' },
          { name: 'stalenessPeriod', internalType: 'uint32', type: 'uint32' },
        ],
      },
      {
        name: 'priceFeedTree',
        internalType: 'struct PriceFeedTreeNode[]',
        type: 'tuple[]',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'description', internalType: 'string', type: 'string' },
          { name: 'decimals', internalType: 'uint8', type: 'uint8' },
          { name: 'skipCheck', internalType: 'bool', type: 'bool' },
          { name: 'updatable', internalType: 'bool', type: 'bool' },
          {
            name: 'underlyingFeeds',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'underlyingStalenessPeriods',
            internalType: 'uint32[]',
            type: 'uint32[]',
          },
          {
            name: 'answer',
            internalType: 'struct PriceFeedAnswer',
            type: 'tuple',
            components: [
              { name: 'price', internalType: 'int256', type: 'int256' },
              { name: 'updatedAt', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'priceFeeds', internalType: 'address[]', type: 'address[]' },
    ],
    name: 'loadPriceFeedTree',
    outputs: [
      {
        name: 'priceFeedTree',
        internalType: 'struct PriceFeedTreeNode[]',
        type: 'tuple[]',
        components: [
          {
            name: 'baseParams',
            internalType: 'struct BaseParams',
            type: 'tuple',
            components: [
              { name: 'addr', internalType: 'address', type: 'address' },
              { name: 'version', internalType: 'uint256', type: 'uint256' },
              {
                name: 'contractType',
                internalType: 'bytes32',
                type: 'bytes32',
              },
              {
                name: 'serializedParams',
                internalType: 'bytes',
                type: 'bytes',
              },
            ],
          },
          { name: 'description', internalType: 'string', type: 'string' },
          { name: 'decimals', internalType: 'uint8', type: 'uint8' },
          { name: 'skipCheck', internalType: 'bool', type: 'bool' },
          { name: 'updatable', internalType: 'bool', type: 'bool' },
          {
            name: 'underlyingFeeds',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'underlyingStalenessPeriods',
            internalType: 'uint32[]',
            type: 'uint32[]',
          },
          {
            name: 'answer',
            internalType: 'struct PriceFeedAnswer',
            type: 'tuple',
            components: [
              { name: 'price', internalType: 'int256', type: 'int256' },
              { name: 'updatedAt', internalType: 'uint256', type: 'uint256' },
              { name: 'success', internalType: 'bool', type: 'bool' },
            ],
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'contractType',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
      {
        name: 'serializer',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'SetSerializer',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IRewardsCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iRewardsCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditAccount', internalType: 'address', type: 'address' },
    ],
    name: 'getRewards',
    outputs: [
      {
        name: 'rewards',
        internalType: 'struct RewardInfo[]',
        type: 'tuple[]',
        components: [
          { name: 'amount', internalType: 'uint256', type: 'uint256' },
          { name: 'rewardToken', internalType: 'address', type: 'address' },
          {
            name: 'stakedPhantomToken',
            internalType: 'address',
            type: 'address',
          },
          { name: 'adapter', internalType: 'address', type: 'address' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ITokenCompressor
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iTokenCompressorAbi = [
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'token', internalType: 'address', type: 'address' }],
    name: 'getTokenInfo',
    outputs: [
      {
        name: 'result',
        internalType: 'struct TokenData',
        type: 'tuple',
        components: [
          { name: 'addr', internalType: 'address', type: 'address' },
          { name: 'symbol', internalType: 'string', type: 'string' },
          { name: 'name', internalType: 'string', type: 'string' },
          { name: 'decimals', internalType: 'uint8', type: 'uint8' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IZapperRegisterLegacy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const iZapperRegisterLegacyAbi = [
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'zappers',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
] as const

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MarketConfiguratorLegacy
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

export const marketConfiguratorLegacyAbi = [
  {
    type: 'constructor',
    inputs: [
      { name: 'addressProvider_', internalType: 'address', type: 'address' },
      { name: 'admin_', internalType: 'address', type: 'address' },
      { name: 'emergencyAdmin_', internalType: 'address', type: 'address' },
      { name: 'curatorName_', internalType: 'string', type: 'string' },
      { name: 'deployGovernor_', internalType: 'bool', type: 'bool' },
      {
        name: 'legacyParams_',
        internalType: 'struct LegacyParams',
        type: 'tuple',
        components: [
          { name: 'acl', internalType: 'address', type: 'address' },
          {
            name: 'contractsRegister',
            internalType: 'address',
            type: 'address',
          },
          { name: 'gearStaking', internalType: 'address', type: 'address' },
          { name: 'zapperRegister', internalType: 'address', type: 'address' },
          {
            name: 'pausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'unpausableAdmins',
            internalType: 'address[]',
            type: 'address[]',
          },
          {
            name: 'emergencyLiquidators',
            internalType: 'address[]',
            type: 'address[]',
          },
          { name: 'bots', internalType: 'address[]', type: 'address[]' },
        ],
      },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'acl',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'aclLegacy',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'peripheryContract', internalType: 'address', type: 'address' },
    ],
    name: 'addPeripheryContract',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'token', internalType: 'address', type: 'address' },
      { name: 'priceFeed', internalType: 'address', type: 'address' },
    ],
    name: 'addToken',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'addressProvider',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'admin',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'factory', internalType: 'address', type: 'address' },
      { name: 'suite', internalType: 'address', type: 'address' },
      { name: 'target', internalType: 'address', type: 'address' },
    ],
    name: 'authorizeFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'bytecodeRepository',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'configureCreditSuite',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'data', internalType: 'bytes', type: 'bytes' }],
    name: 'configureGearStaking',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'configureInterestRateModel',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'configureLossPolicy',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'configurePool',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'configurePriceOracle',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'configureRateKeeper',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'contractType',
    outputs: [{ name: '', internalType: 'bytes32', type: 'bytes32' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'contractsRegister',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'contractsRegisterLegacy',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'minorVersion', internalType: 'uint256', type: 'uint256' },
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'encodedParams', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'createCreditSuite',
    outputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'minorVersion', internalType: 'uint256', type: 'uint256' },
      { name: 'underlying', internalType: 'address', type: 'address' },
      { name: 'name', internalType: 'string', type: 'string' },
      { name: 'symbol', internalType: 'string', type: 'string' },
      {
        name: 'interestRateModelParams',
        internalType: 'struct DeployParams',
        type: 'tuple',
        components: [
          { name: 'postfix', internalType: 'bytes32', type: 'bytes32' },
          { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
          { name: 'constructorParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
      {
        name: 'rateKeeperParams',
        internalType: 'struct DeployParams',
        type: 'tuple',
        components: [
          { name: 'postfix', internalType: 'bytes32', type: 'bytes32' },
          { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
          { name: 'constructorParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
      {
        name: 'lossPolicyParams',
        internalType: 'struct DeployParams',
        type: 'tuple',
        components: [
          { name: 'postfix', internalType: 'bytes32', type: 'bytes32' },
          { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
          { name: 'constructorParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
      { name: 'underlyingPriceFeed', internalType: 'address', type: 'address' },
    ],
    name: 'createMarket',
    outputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'crossChainGovernanceProxy',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'curatorName',
    outputs: [{ name: '', internalType: 'string', type: 'string' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [],
    name: 'emergencyAdmin',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'emergencyConfigureCreditSuite',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'emergencyConfigureInterestRateModel',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'emergencyConfigureLossPolicy',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'emergencyConfigurePool',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'emergencyConfigurePriceOracle',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'data', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'emergencyConfigureRateKeeper',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'emergencyRevokeRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'finalizeMigration',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'gearStakingLegacy',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'target', internalType: 'address', type: 'address' }],
    name: 'getAuthorizedFactory',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'getCreditFactory',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'factory', internalType: 'address', type: 'address' },
      { name: 'suite', internalType: 'address', type: 'address' },
    ],
    name: 'getFactoryTargets',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'getMarketFactories',
    outputs: [
      {
        name: '',
        internalType: 'struct MarketFactories',
        type: 'tuple',
        components: [
          { name: 'poolFactory', internalType: 'address', type: 'address' },
          {
            name: 'priceOracleFactory',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'interestRateModelFactory',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'rateKeeperFactory',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'lossPolicyFactory',
            internalType: 'address',
            type: 'address',
          },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [{ name: 'domain', internalType: 'bytes32', type: 'bytes32' }],
    name: 'getPeripheryContracts',
    outputs: [{ name: '', internalType: 'address[]', type: 'address[]' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'grantRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'initializeCreditSuite',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'initializeMarket',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'domain', internalType: 'bytes32', type: 'bytes32' },
      { name: 'peripheryContract', internalType: 'address', type: 'address' },
    ],
    name: 'isPeripheryContract',
    outputs: [{ name: '', internalType: 'bool', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'marketMinorVersion', internalType: 'uint256', type: 'uint256' },
      {
        name: 'creditSuiteMinorVersion',
        internalType: 'uint256',
        type: 'uint256',
      },
      { name: 'underlying', internalType: 'address', type: 'address' },
      { name: 'name', internalType: 'string', type: 'string' },
      { name: 'symbol', internalType: 'string', type: 'string' },
      { name: 'encodedParams', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'previewCreateCreditSuite',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'minorVersion', internalType: 'uint256', type: 'uint256' },
      { name: 'pool', internalType: 'address', type: 'address' },
      { name: 'encodedParams', internalType: 'bytes', type: 'bytes' },
    ],
    name: 'previewCreateCreditSuite',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'minorVersion', internalType: 'uint256', type: 'uint256' },
      { name: 'underlying', internalType: 'address', type: 'address' },
      { name: 'name', internalType: 'string', type: 'string' },
      { name: 'symbol', internalType: 'string', type: 'string' },
    ],
    name: 'previewCreateMarket',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'peripheryContract', internalType: 'address', type: 'address' },
    ],
    name: 'removePeripheryContract',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32' },
      { name: 'account', internalType: 'address', type: 'address' },
    ],
    name: 'revokeRole',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'newEmergencyAdmin', internalType: 'address', type: 'address' },
    ],
    name: 'setEmergencyAdmin',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'shutdownCreditSuite',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'shutdownMarket',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'treasury',
    outputs: [{ name: '', internalType: 'address', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    inputs: [
      { name: 'factory', internalType: 'address', type: 'address' },
      { name: 'suite', internalType: 'address', type: 'address' },
      { name: 'target', internalType: 'address', type: 'address' },
    ],
    name: 'unauthorizeFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      {
        name: 'params',
        internalType: 'struct DeployParams',
        type: 'tuple',
        components: [
          { name: 'postfix', internalType: 'bytes32', type: 'bytes32' },
          { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
          { name: 'constructorParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'updateInterestRateModel',
    outputs: [
      { name: 'interestRateModel', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      {
        name: 'params',
        internalType: 'struct DeployParams',
        type: 'tuple',
        components: [
          { name: 'postfix', internalType: 'bytes32', type: 'bytes32' },
          { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
          { name: 'constructorParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'updateLossPolicy',
    outputs: [{ name: 'lossPolicy', internalType: 'address', type: 'address' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'updatePriceOracle',
    outputs: [
      { name: 'priceOracle', internalType: 'address', type: 'address' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address' },
      {
        name: 'params',
        internalType: 'struct DeployParams',
        type: 'tuple',
        components: [
          { name: 'postfix', internalType: 'bytes32', type: 'bytes32' },
          { name: 'salt', internalType: 'bytes32', type: 'bytes32' },
          { name: 'constructorParams', internalType: 'bytes', type: 'bytes' },
        ],
      },
    ],
    name: 'updateRateKeeper',
    outputs: [{ name: 'rateKeeper', internalType: 'address', type: 'address' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'upgradeCreditFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'upgradeInterestRateModelFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'upgradeLossPolicyFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'upgradePoolFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'upgradePriceOracleFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'upgradeRateKeeperFactory',
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    inputs: [],
    name: 'version',
    outputs: [{ name: '', internalType: 'uint256', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'domain',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
      {
        name: 'peripheryContract',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'AddPeripheryContract',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'token',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'AddToken',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'suite',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'target',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'AuthorizeFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'creditManager',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'ConfigureCreditSuite',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'ConfigureInterestRateModel',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'ConfigureLossPolicy',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'ConfigurePool',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'ConfigurePriceOracle',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'ConfigureRateKeeper',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'creditManager',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'CreateCreditSuite',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'priceOracle',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'interestRateModel',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'rateKeeper',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'lossPolicy',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
      {
        name: 'factories',
        internalType: 'struct MarketFactories',
        type: 'tuple',
        components: [
          { name: 'poolFactory', internalType: 'address', type: 'address' },
          {
            name: 'priceOracleFactory',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'interestRateModelFactory',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'rateKeeperFactory',
            internalType: 'address',
            type: 'address',
          },
          {
            name: 'lossPolicyFactory',
            internalType: 'address',
            type: 'address',
          },
        ],
        indexed: false,
      },
    ],
    name: 'CreateMarket',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'creditManager',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'EmergencyConfigureCreditSuite',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'EmergencyConfigureInterestRateModel',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'EmergencyConfigureLossPolicy',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'EmergencyConfigurePool',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'EmergencyConfigurePriceOracle',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      { name: 'data', internalType: 'bytes', type: 'bytes', indexed: false },
    ],
    name: 'EmergencyConfigureRateKeeper',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'EmergencyRevokeRole',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'target',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'callData',
        internalType: 'bytes',
        type: 'bytes',
        indexed: false,
      },
    ],
    name: 'ExecuteHook',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'GrantRole',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'domain',
        internalType: 'bytes32',
        type: 'bytes32',
        indexed: true,
      },
      {
        name: 'peripheryContract',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'RemovePeripheryContract',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'role', internalType: 'bytes32', type: 'bytes32', indexed: true },
      {
        name: 'account',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'RevokeRole',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'newEmergencyAdmin',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'SetEmergencyAdmin',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'creditManager',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'ShutdownCreditSuite',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
    ],
    name: 'ShutdownMarket',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'suite',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'target',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
    ],
    name: 'UnauthorizeFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'interestRateModel',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpdateInterestRateModel',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'lossPolicy',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpdateLossPolicy',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'priceOracle',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpdatePriceOracle',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'rateKeeper',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpdateRateKeeper',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      {
        name: 'creditManager',
        internalType: 'address',
        type: 'address',
        indexed: true,
      },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpgradeCreditFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpgradeInterestRateModelFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpgradeLossPolicyFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpgradePoolFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpgradePriceOracleFactory',
  },
  {
    type: 'event',
    anonymous: false,
    inputs: [
      { name: 'pool', internalType: 'address', type: 'address', indexed: true },
      {
        name: 'factory',
        internalType: 'address',
        type: 'address',
        indexed: false,
      },
    ],
    name: 'UpgradeRateKeeperFactory',
  },
  { type: 'error', inputs: [], name: 'ACLOwnershipNotTransferredException' },
  {
    type: 'error',
    inputs: [{ name: 'admin', internalType: 'address', type: 'address' }],
    name: 'AddressIsNotPausableAdminException',
  },
  {
    type: 'error',
    inputs: [{ name: 'admin', internalType: 'address', type: 'address' }],
    name: 'AddressIsNotUnpausableAdminException',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'CallerIsNotAdminException',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'CallerIsNotCrossChainGovernanceProxyException',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'CallerIsNotEmergencyAdminException',
  },
  {
    type: 'error',
    inputs: [{ name: 'caller', internalType: 'address', type: 'address' }],
    name: 'CallerIsNotSelfException',
  },
  {
    type: 'error',
    inputs: [],
    name: 'CallsToLegacyContractsAreForbiddenException',
  },
  {
    type: 'error',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
      { name: 'token', internalType: 'address', type: 'address' },
    ],
    name: 'CollateralTokenIsNotQuotedException',
  },
  {
    type: 'error',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'CreditSuiteAlreadyInitializedException',
  },
  {
    type: 'error',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'CreditSuiteIsNotInitializedException',
  },
  {
    type: 'error',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'CreditSuiteNotRegisteredException',
  },
  { type: 'error', inputs: [], name: 'ForceApproveFailed' },
  {
    type: 'error',
    inputs: [
      { name: 'creditManager', internalType: 'address', type: 'address' },
    ],
    name: 'InconsistentPriceOracleException',
  },
  {
    type: 'error',
    inputs: [{ name: 'version', internalType: 'uint256', type: 'uint256' }],
    name: 'IncorrectMinorVersionException',
  },
  {
    type: 'error',
    inputs: [
      { name: 'peripheryContract', internalType: 'address', type: 'address' },
    ],
    name: 'IncorrectPeripheryContractException',
  },
  {
    type: 'error',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'MarketAlreadyInitializedException',
  },
  {
    type: 'error',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'MarketIsNotInitializedException',
  },
  {
    type: 'error',
    inputs: [{ name: 'pool', internalType: 'address', type: 'address' }],
    name: 'MarketNotRegisteredException',
  },
  {
    type: 'error',
    inputs: [
      { name: 'factory', internalType: 'address', type: 'address' },
      { name: 'target', internalType: 'address', type: 'address' },
    ],
    name: 'UnauthorizedFactoryException',
  },
] as const
