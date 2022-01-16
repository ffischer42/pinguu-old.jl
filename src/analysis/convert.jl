function price2string(price, precision; round_up=false)
    if price <= 0.0001
        if round_up
            return "0."*lpad(Int(ceil(price * 10^precision)), precision, "0")
        else
            return "0."*lpad(Int(floor(price * 10^precision)), precision, "0")
        end
    else
        if round_up
            return string(ceil(price, digits=precision))
        else
            return string(floor(price, digits=precision))
        end
    end
end
export price2string



function get_precision(client, symbol)
    info = client.get_symbol_info(symbol)

    min_qty = parse(Float64, info["filters"][4]["minNotional"])
    stepSize  = parse(Float64, info["filters"][3]["stepSize"])
    buy_precision = 0
    while true
        if stepSize * 10^buy_precision == 1
            break
        end
        buy_precision += 1
    end

    tickSize = parse(Float64, info["filters"][1]["tickSize"])
    sell_precision = 0
    while tickSize * 10^sell_precision < 1
        sell_precision += 1
    end
    return buy_precision, sell_precision, min_qty, stepSize, tickSize
end
export get_precision