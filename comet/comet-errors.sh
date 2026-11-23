# Sourced by swap-usdc.sh / swap-blnt.sh.
# Turns the raw `stellar contract invoke` error into something readable.
#
# Usage: explain_comet_error <stderr_file> <pool_id> <token_in> <token_out> <max_price_stroops>

# Comet pool contract errors (comet-contracts-v1/contracts/src/c_pool/error.rs)
comet_error_name() {
    case $1 in
        1) echo ErrFinalized ;;            2) echo ErrNegative ;;
        3) echo ErrMinFee ;;               4) echo ErrMaxFee ;;
        5) echo ErrNotController ;;        6) echo ErrInvalidVectorLen ;;
        7) echo AlreadyInitialized ;;      8) echo ErrIsBound ;;
        9) echo ErrNotBound ;;             10) echo ErrMaxTokens ;;
        11) echo ErrMinWeight ;;           12) echo ErrMaxWeight ;;
        13) echo ErrMinBalance ;;          14) echo ErrFreezeOnlyWithdrawals ;;
        15) echo ErrMinTokens ;;           16) echo ErrSwapFee ;;
        17) echo ErrMaxInRatio ;;          18) echo ErrMathApprox ;;
        19) echo ErrLimitIn ;;             20) echo ErrLimitOut ;;
        21) echo ErrMaxOutRatio ;;         22) echo ErrBadLimitPrice ;;
        23) echo ErrLimitPrice ;;          24) echo ErrTotalWeight ;;
        25) echo ErrTokenAmountIsNegative ;; 26) echo ErrNotAuthorizedByAdmin ;;
        27) echo ErrInsufficientAllowance ;; 28) echo ErrDeauthorized ;;
        29) echo ErrInsufficientBalance ;; 30) echo ErrAddOverflow ;;
        31) echo ErrSubUnderflow ;;        32) echo ErrDivInternal ;;
        33) echo ErrMulOverflow ;;         34) echo ErrCPowBaseTooLow ;;
        35) echo ErrCPowBaseTooHigh ;;     36) echo ErrInvalidExpirationLedger ;;
        37) echo ErrNegativeOrZero ;;      38) echo ErrTokenInvalid ;;
        39) echo ErrSameToken ;;           *) echo "unknown" ;;
    esac
}

# current spot price (incl. fee) in token_in per token_out, 7-decimal stroops
comet_spot_price() {
    stellar contract invoke --id $1 --source-account xbull --network mainnet \
        --send=no -- get_spot_price --token_in $2 --token_out $3 2>/dev/null \
        | tr -d '"'
}

stroops() {
    perl -e 'printf("%0.7f", '"$1"'/10000000)'
}

token_label() {
    case $1 in
        CCW67TSZV3SSS2HXMBQ5JFGCKJNXKZM7UQUWUZPUTHXSTZLEO7SJMI75) echo USDC ;;
        CCBNWP5L7ZSXA3DBWCMFAVKFVRW3ZHWO7B5J557W42O64DDZNPJP7VDS) echo BLNT ;;
        *) echo $1 ;;
    esac
}

explain_comet_error() {
    local errfile=$1 pool=$2 tin=$3 tout=$4 maxp=$5
    local code
    code=`grep -oE 'Error\(Contract, #[0-9]+\)' $errfile | head -1 | grep -oE '[0-9]+'`
    [ -z "$code" ] && code=`grep -oE '#[0-9]+' $errfile | head -1 | tr -d '#'`

    echo
    echo "================================================================"
    if [ -z "$code" ]; then
        echo "swap FAILED (not a contract error; see raw output above)"
        echo "================================================================"
        return
    fi

    case $code in
    22)
        local spot=`comet_spot_price $pool $tin $tout`
        echo "swap FAILED: #22 ErrBadLimitPrice"
        echo "  The pool's price is ALREADY worse than your max price, before"
        echo "  any swap happens. Nothing was traded."
        echo "  max price:  `stroops $maxp`"
        [ -n "$spot" ] && echo "  spot price: `stroops $spot`  (incl. fee)"
        echo "  -> wait for the pool to move, or raise the max price."
        ;;
    23)
        local spot=`comet_spot_price $pool $tin $tout`
        echo "swap FAILED: #23 ErrLimitPrice"
        echo "  The pool price is OK now, but this swap would push the price"
        echo "  past your max price. Nothing was traded."
        echo "  max price:  `stroops $maxp`"
        [ -n "$spot" ] && echo "  spot price: `stroops $spot`  (incl. fee, before swap)"
        echo "  -> use a smaller amount, or raise the max price."
        ;;
    10)
        # ErrMaxTokens (10) is only raised at pool init, so during a swap
        # #10 comes from the token contract: SAC BalanceError.
        echo "swap FAILED: #10 insufficient balance (token BalanceError)"
        echo "  The xbull wallet doesn't hold enough of the input token"
        echo "  (`token_label $tin`) to cover the swap amount."
        echo "  -> check balances, or swap a smaller amount."
        ;;
    *)
        echo "swap FAILED: #$code `comet_error_name $code`"
        ;;
    esac
    echo "================================================================"
}
