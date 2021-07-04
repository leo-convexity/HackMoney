// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "OpenZeppelin/openzeppelin-contracts@4.1.0/contracts/token/ERC20/IERC20.sol";
import "OpenZeppelin/openzeppelin-contracts@4.1.0/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Clones} from "OpenZeppelin/openzeppelin-contracts@4.1.0/contracts/proxy/Clones.sol";
import {Address} from "OpenZeppelin/openzeppelin-contracts@4.1.0/contracts/utils/Address.sol";
import "contracts/CTokenInterfaces.sol";
import "contracts/ICErc20.sol";
import "contracts/ICEther.sol";
import "interfaces/ComptrollerInterface.sol";
import "interfaces/IWETH.sol";
import "interfaces/IUniswapV2Factory.sol";
import "interfaces/IUniswapV2Pair.sol";
import "interfaces/IUniswapV2Router02.sol";
import "interfaces/IUniswapV2Router02.sol";
import "contracts/FutureToken.sol";

address constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

abstract contract ProxyWalletData {
    address internal _owner;
    address internal _proxy_wallet;

    function _initialize(address newOwner) internal {
	assembly { if gt(_owner.slot, 0) { revert(0, 0) } } // dev: owner slot is not zero
	require(_owner == address(0)); // dev: contract already initialized

	_owner = newOwner;
	_proxy_wallet = msg.sender;
    }
}

abstract contract ProxyWalletImpl is ProxyWalletData {
    event WalletAllocated(address indexed owner, address wallet);
    event WalletCreated(address indexed owner, address wallet);
    event WalletDestroyed(address indexed owner, address wallet);
    event WalletDeposit(
	address indexed _from,
	address indexed _deposit_token,
	address indexed _ctoken,
	uint _deposit_value,
	uint _ctoken_value,
	uint _rate_before,
	uint _rate_after
    );

    modifier onlyOwner() {
        require(_owner == msg.sender); // dev: Ownable: caller is not the owner
        _;
    }

    modifier onlyIfOriginal() {
        require(_proxy_wallet == address(0)); // dev: only callable on original contract
        _;
    }

    function owner() view public returns (address) { return _owner; }

    function isProxy() view public returns (bool result) {
	assembly {
	    result := iszero(eq(codesize(), extcodesize(address())))
	}
    }

    function extractProxyAddress() view public returns (address a) {
	assembly {
	    extcodecopy(address(), 0, 0, 32)
	    codecopy(32, 0, 32)
	    a := mload(0)
	    if eq(a, mload(32)) { a := 0 }
	    a := shr(16, a)
	}
    }
}

contract ProxyWallet is ProxyWalletImpl {
    using Clones for address;
    using Address for address;

    FutureToken internal _future_token;
    ComptrollerInterface _compound_comptroller;
    IUniswapV2Router02 internal _uniswap_router;

    mapping(address => CTokenInterface) internal _token_to_ctoken;
    ICEther internal _cether;

    constructor(FutureToken future_token,
		ComptrollerInterface compound_comptroller,
		IUniswapV2Router02 uniswap_router) {
	_owner = msg.sender;
	//_proxy_wallet = this;
	_future_token = future_token;
	_compound_comptroller = compound_comptroller;
	_uniswap_router = uniswap_router;

	/*
	address[] memory ctokens = compound_comptroller.getAllMarkets();
	uint num_ctokens = ctokens.length;
	for (uint i = 0; i < num_ctokens; ++i) {
	    address ctoken = ctokens[i];
	    _token_to_ctoken[ctoken] = CTokenInterface(ctoken);
	    ICErc20 ctoken_as_erc20 = ICErc20(ctoken);
	    try ctoken_as_erc20.underlying() returns (address underlying) {
		_token_to_ctoken[underlying] = CTokenInterface(ctoken);
	    } catch {
		// CEther doesn't have an underlying() method
		_token_to_ctoken[ETH_TOKEN_ADDRESS] = CTokenInterface(ctoken);
		_cether = ICEther(payable(ctoken));
	    }
	}
	*/
    }

    function addCEtherToken(ICEther cether) external onlyOwner onlyIfOriginal {
	require(address(cether) != address(0)); // dev: argument must be non-zero
	require(address(_cether) == address(0)); // dev: CEther already added
	_token_to_ctoken[address(cether)] = CTokenInterface(cether);
	_token_to_ctoken[ETH_TOKEN_ADDRESS] = CTokenInterface(cether);
	_cether = cether;
    }

    function addCErc20Token(ICErc20 ctoken) external onlyOwner onlyIfOriginal {
	require(address(ctoken) != address(0)); // dev: argument must be non-zero
	require(address(_token_to_ctoken[address(ctoken)]) == address(0)); // dev: CToken already added
	address underlying = ctoken.underlying();
	require(underlying != address(0)); // dev: missing underlying
	_token_to_ctoken[address(ctoken)] = ctoken;
	_token_to_ctoken[underlying] = ctoken;
    }

    struct PricingData {
	uint exchange_rate;
	uint expiry;
	uint reserves_fut_long;
	uint reserves_ctoken_long;
	uint reserves_fut_short;
	uint reserves_ctoken_short;
	uint32 timestamp_fut_ctoken_long;
	uint32 timestamp_fut_ctoken_short;
	address ctoken;
	address fut_class;
	address fut_long;
	address fut_short;
	address uni_fut_ctoken_long;
	address uni_fut_ctoken_short;
    }

    function getPricing(address token, uint blocks) external returns (PricingData memory x) {
	(FutureToken fut,
	 /*IUniswapV2Router02*/,
	 IUniswapV2Factory uniswap_factory,
	 CTokenInterface ctoken_intf) = _getProxyCommonData(token);
	x.ctoken = address(ctoken_intf);
	x.exchange_rate = ctoken_intf.exchangeRateCurrent();
	x.expiry = fut.calcExpiryBlock(blocks);
	(x.fut_class, x.fut_long, x.fut_short) = fut.getExpiryClassLongShort(ctoken_intf, x.expiry);
	if (x.fut_long != address(0)) {
	    x.uni_fut_ctoken_long = uniswap_factory.getPair(x.fut_long, x.ctoken);
	    if (x.uni_fut_ctoken_long != address(0)) {
		(x.reserves_fut_long, x.reserves_ctoken_long, x.timestamp_fut_ctoken_long) = IUniswapV2Pair(x.uni_fut_ctoken_long).getReserves();
		if (x.fut_long > x.ctoken) {
		    (x.reserves_fut_long, x.reserves_ctoken_long) = (x.reserves_ctoken_long, x.reserves_fut_long);
		}
	    }
	}
	if (x.fut_short != address(0)) {
	    x.uni_fut_ctoken_short = uniswap_factory.getPair(x.fut_short, x.ctoken);
	    if (x.uni_fut_ctoken_short != address(0)) {
		(x.reserves_fut_short, x.reserves_ctoken_short, x.timestamp_fut_ctoken_short) = IUniswapV2Pair(x.uni_fut_ctoken_short).getReserves();
		if (x.fut_short > x.ctoken) {
		    (x.reserves_fut_short, x.reserves_ctoken_short) = (x.reserves_ctoken_short, x.reserves_fut_short);
		}
	    }
	}
    }

    function getBalance(address token) view external returns (uint) {
	if (token == ETH_TOKEN_ADDRESS)
	    return address(this).balance;
	else
	    return IERC20(token).balanceOf(address(this));
    }

    function deposit(uint amount, address token) external payable onlyOwner returns (bool) {
	(FutureToken _ignore0,
	 IUniswapV2Router02 _ignore1,
	 IUniswapV2Factory _ignore2,
	 CTokenInterface ctoken_intf) = _getProxyCommonData(token);
	if (token == ETH_TOKEN_ADDRESS) {
	    assert(amount >= msg.value); // dev: supplied ether less than amount required
	    if (amount < msg.value) {
		uint refund = msg.value - amount;
		(bool sent, bytes memory data) = msg.sender.call{value: refund}("");
		require(sent); // dev: failed to refund excess deposit amount
	    }
	    ICEther cether = ICEther(payable(address(ctoken_intf)));
	    return _deposit_ether(amount, cether);
	}
	address ctoken = address(ctoken_intf);
	if (token != ctoken)
	    return _deposit_erc20(amount, IERC20(token), ICErc20(ctoken));
	else
	    return _deposit_ctoken(amount, ICErc20(ctoken));
    }

    function _deposit_ether(uint amount, ICEther cether) internal returns (bool) {
	require(amount > 0); // dev: amount is zero

	uint balance_before = cether.balanceOf(address(this));
	uint rate_before = cether.exchangeRateCurrent();
	cether.mint{value: amount}();
	uint balance_minted = cether.balanceOf(address(this)) - balance_before;
	uint rate_after = cether.exchangeRateCurrent();
	require(balance_minted > 0); // dev: nothing minted

	emit WalletDeposit(msg.sender, ETH_TOKEN_ADDRESS, address(cether), amount, balance_minted, rate_before, rate_after);
	return true;
    }

    function _deposit_erc20(uint amount, IERC20 token, ICErc20 ctoken) internal returns (bool) {
	require(amount > 0); // dev: amount is zero
	require(address(token) != address(ctoken)); // dev: token cannot be a ctoken

	require(token.transferFrom(msg.sender, address(this), amount)); // dev: token transfer failed
	require(token.approve(address(ctoken), amount)); //dev : approve ctoken failed
	uint balance_before = ctoken.balanceOf(address(this));
	uint rate_before = ctoken.exchangeRateCurrent();
	{
	    uint rc = ctoken.mint(amount);
	    if (rc != 0) {
		bytes memory text = "deposit:3:\x00";
		text[10] = bytes1(64 + (uint8(rc) & 0x1f));
		revert(string(text));
	    }
	}
	uint balance_minted = ctoken.balanceOf(address(this)) - balance_before;
	uint rate_after = ctoken.exchangeRateCurrent();
	require(balance_minted > 0); // dev: nothing minted

	emit WalletDeposit(msg.sender, address(token), address(ctoken), amount, balance_minted, rate_before, rate_after);
	return true;
    }

    function _deposit_ctoken(uint amount, ICErc20 ctoken) internal returns (bool) {
	require(amount > 0); // dev: amount is zero

	uint balance_before = ctoken.balanceOf(address(this));
	uint rate_before = ctoken.exchangeRateCurrent();
	require(ctoken.transferFrom(msg.sender, address(this), amount)); // dev: token transfer failed
	uint balance_minted = ctoken.balanceOf(address(this)) - balance_before;
	uint rate_after = ctoken.exchangeRateCurrent();
	require(balance_minted > 0); // dev: nothing minted

	emit WalletDeposit(msg.sender, address(ctoken), address(ctoken), amount, balance_minted, rate_before, rate_after);
	return true;
    }

    function _getProxyCommonData(address asset) view internal returns (FutureToken, IUniswapV2Router02, IUniswapV2Factory, CTokenInterface) {
	return ProxyWallet(payable(_proxy_wallet)).getProxyCommonData(asset);
    }

    function getProxyCommonData(address asset) view external returns (FutureToken, IUniswapV2Router02, IUniswapV2Factory, CTokenInterface) {
	address factory = _uniswap_router.factory();
	address ctoken = address(_token_to_ctoken[asset]);
	require(ctoken != address(0)); // dev: asset not recognised
	return (_future_token,
		_uniswap_router,
		IUniswapV2Factory(factory),
		CTokenInterface(ctoken));
    }

    fallback(bytes calldata /*_input*/) external payable returns (bytes memory /*_output*/) { revert(); } // dev: no fallback

    receive() external payable { revert(); } // dev: no receive

    function initializeWallet(address owner) external {
	require(Clones.predictDeterministicAddress(msg.sender,
						   bytes32(uint256(uint160(owner))),
						   msg.sender) == address(this)); // dev: must be called by deployer
	super._initialize(owner);
	emit WalletCreated(owner, address(this));
    }

    function getWalletAddress() view public returns (address) {
	return Clones.predictDeterministicAddress(address(this), bytes32(uint256(uint160(msg.sender))));
    }

    function getWalletOrNull() view external returns (ProxyWallet) {
	address addr = getWalletAddress();
	if (!addr.isContract()) addr = address(0);
	return ProxyWallet(payable(addr));
    }

    function getWallet() view external returns (ProxyWallet) {
	address addr = getWalletAddress();
	require(addr.isContract()); // dev: clone not created
	return ProxyWallet(payable(addr));
    }

    function destroyWallet() external {
	require(_owner == msg.sender); // dev: Ownable: caller is not the owner
	require(isProxy()); // dev: only proxies can be destroyed
	selfdestruct(payable(msg.sender));
	emit WalletCreated(msg.sender, address(this));
    }

    function createWalletIfNeeded() external returns (ProxyWallet) {
	address addr = getWalletAddress();
	if (!addr.isContract()) {
            require(!isProxy()); // dev: cannot create clone from clone
	    Clones.cloneDeterministic(address(this), bytes32(uint256(uint160(msg.sender))));
	    emit WalletAllocated(msg.sender, addr);
	    ProxyWallet(payable(addr)).initializeWallet(msg.sender);
	}
	return ProxyWallet(payable(addr));
    }
}