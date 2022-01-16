function analyse_tmp_order(client, config, bot_path, trade_path)
    tmp = JSON.parsefile(trade_path)
    #
    ## Get trades of SELL order
    if !haskey(tmp, "order_trades")
        tmp["order_trades"] = client.get_my_trades(symbol=config["symbol"], orderId=tmp["order"]["orderId"])
        open(trade_path, "w") do f
            JSON.print(f, tmp, 4)
        end
    end
    if !haskey(tmp["order"], "fee")
        tmp["order"]["fee"] = Pinguu.calc_order_fee(client, tmp["order_trades"], config)
        open(trade_path, "w") do f
            JSON.print(f, tmp, 4)
        end
    end
    #
    ## Get trades of BUY order (if exists)
    if haskey(tmp, "buy_order")
        if !haskey(tmp, "buy_order_trades")
            tmp["buy_order_trades"] = client.get_my_trades(symbol=config["symbol"], orderId=tmp["buy_order"]["orderId"])
            open(trade_path, "w") do f
                JSON.print(f, tmp, 4)
            end
        end
        if !haskey(tmp["buy_order"], "fee")
            tmp["buy_order"]["fee"] = Pinguu.calc_order_fee(client, tmp["buy_order_trades"], config)
            open(trade_path, "w") do f
                JSON.print(f, tmp, 4)
            end
        end
    end
    if tmp["type"] == "normal"
        paid = typeof(tmp["buy_order"]["cummulativeQuoteQty"]) != Float64 ? parse(Float64, tmp["buy_order"]["cummulativeQuoteQty"]) : tmp["buy_order"]["cummulativeQuoteQty"]
        got = typeof(tmp["order"]["cummulativeQuoteQty"]) != Float64 ? parse(Float64, tmp["order"]["cummulativeQuoteQty"]) : tmp["order"]["cummulativeQuoteQty"]
        fees = tmp["buy_order"]["fee"] + tmp["order"]["fee"]
    elseif tmp["type"] == "initial"
        price = typeof(config["init_state"]["price"]) != Float64 ? parse(Float64, config["init_state"]["price"]) : config["init_state"]["price"]
        got = typeof(tmp["order"]["cummulativeQuoteQty"]) != Float64 ? parse(Float64, tmp["order"]["cummulativeQuoteQty"]) : tmp["order"]["cummulativeQuoteQty"]
        paid = got * price/parse(Float64, tmp["order"]["price"])
        fees = tmp["order"]["fee"]
        fees += config["init_state"]["fee"] * (paid / config["init_state"]["cummulativeQuoteQty"])
    end
    profit = got - paid - fees
    tmp["profit"] = profit

    current_volume = Pinguu.get_current_volume(config)
    
    tmp["profit_percent"] = tmp["profit"] * 100 / current_volume
    tmp["profit_thes"] = tmp["profit"] * config["thes_factor"]
    
    tmp["fee"] = fees
    tmp["analysed"] = 1
    open(trade_path, "w") do f
        JSON.print(f, tmp, 4)
    end
    return tmp
end
export analyse_tmp_order


function analyse_closed_order(client, config, bot_path, trade_path)
    tmp = Pinguu.analyse_tmp_order(client, config, bot_path, trade_path)
    
    #
    ## Write to closed orders
    yr, m = split(string(now()), "-")[1:2]
    current_closed_orders_path = joinpath(bot_path, "history/" * yr * "/" * m * ".json")
    !isdir(dirname(current_closed_orders_path)) ? mkpath(dirname(current_closed_orders_path)) : ""
    closed_orders = isfile(current_closed_orders_path) ? JSON.parsefile(current_closed_orders_path) : Dict()
    !haskey(closed_orders, string(today())) ? closed_orders[string(today())] = [] : ""
    push!(closed_orders[string(today())], tmp)
    open(current_closed_orders_path, "w") do f
        JSON.print(f, closed_orders, 4)
    end
    
    #
    ## Move to corresponding closed orders dir
    if tmp["type"] == "normal"
        mv(trade_path, joinpath(bot_path, "closed_orders/" * basename(trade_path)))
    elseif tmp["type"] == "initial"
        mv(trade_path, joinpath(bot_path, "closed_init_orders/" * basename(trade_path)))
    end
    
    trade_grid = JSON.parsefile(joinpath(bot_path, "trade_grid.json"))
    current_index = findfirst(x->x == tmp["price"], sort(string.(keys(trade_grid))))
    
    msg = "{" * config["name"] * "} Profit: " * string(round(tmp["profit"], digits=2)) * " €"
    msg *= " (" * string(current_index) * "/" * string(length(trade_grid)) * ")"
    if config["telegram"] == "1"
        a = @task send_telegram_msg(config, msg, "/home/felix/pinguu/wp_data/telegram.json")
        schedule(a)
    end
end
export analyse_closed_order

function anaylse_closed_orders(client, config, bot_path; limit=2)
    new_closed = glob(joinpath(bot_path[2:end], "temp/new_closed*.json"));
    if length(new_closed) > limit
        new_closed = new_closed[1:limit]
    end
    for trade_path in new_closed
        Pinguu.analyse_closed_order(client, config, bot_path, trade_path)
    end
end
export analyse_closed_orders


function send_telegram_msg(config, msg::String, telegram_path::String)
    telegram = JSON.parsefile(telegram_path)
    TelegramClient(telegram["token"]; chat_id=telegram[string(config["user_id"])])
    sendMessage(text = msg)
end
export send_telegram_msg