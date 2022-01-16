function place_init_grid_order(client, config)
    val = parse(Float64, config["total_value"]) * parse(Float64, config["init_state"]["init_fraction"])/100
    price = client.get_ticker(symbol = config["symbol"])["lastPrice"]
    current = parse(Float64, price)
    qty = floor(val / current, digits=config["precision"])
    
    if config["testing"] == "1"
        order = try client.create_test_order(
            symbol=config["symbol"],
            side=client.SIDE_BUY,
            type=client.ORDER_TYPE_LIMIT,
            timeInForce=client.TIME_IN_FORCE_GTC,
            quantity=qty,
            price=price
        );
        catch
            nothing
        end
        if order !== nothing
            order = Dict(
                "price" => price,
                "orderId" => 42,
                "executedQty" => "0.00",
                "origQty" => string(qty),
                "side" => client.SIDE_BUY,
                "type" => "limit",
                "symbol" => config["symbol"],
                "status" => "NEW",
                "cummulativeQuoteQty" => "0.00000000",
            )
        else
            return nothing
        end
    else
        order = try client.order_limit_buy(
            symbol=config["symbol"],
            quantity=qty,
            price=price
        );
        catch
            nothing
        end
        if order === nothing
            return nothing
        end
    end
    order["time"] = string(now())
    return order
end
export place_init_grid_order


function check_init_grid_order(client, config)
    if config["testing"] == "1"
        ticker_file = joinpath(Pinguu.base_dir, "wp_data/ticker/" * config["symbol"] * "_kline_1m_candle.json")
        ticker_data = JSON.parsefile(ticker_file);
        ticker = Pinguu.price2string(ticker_data[end][end], config["sell_precision"])
        tmp = deepcopy(config["init_state"]["order"])
        @info("Current: " * ticker)
        @info("Buy: " * tmp["price"])
        if parse(Float64, tmp["price"]) >= parse(Float64, ticker)
            tmp["status"] = client.ORDER_STATUS_FILLED
            tmp["executedQty"] = tmp["origQty"]
            tmp["cummulativeQuoteQty"] = round(parse(Float64, tmp["price"]) * parse(Float64, tmp["origQty"]), digits=config["sell_precision"])
        end
    else
        tmp = try client.get_order(symbol=config["symbol"], orderId=config["init_state"]["order"]["orderId"])
        catch
            return nothing
        end
    end
    return tmp
end
export check_init_grid_order