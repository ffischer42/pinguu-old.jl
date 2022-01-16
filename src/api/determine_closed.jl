function determine_closed(closed_order, id_str, client, status, config; weightedAvgTranslator = 0)
    tmp = deepcopy(closed_order)
    sell_date, sell_time  = split(tmp["SELL"]["time"], "T")
    yr, M, d   = split(sell_date, "-")
    new_closed = Dict()
    new_closed["orders"] = tmp
    @info(id_str)
    sleep(1)
    tmp_vol    = 0
    tmp_pro    = 0
    timestamps = []
    order      = Dict()
    new_closed["buys_exec"] = 0
    new_closed["commission"] = 0
    new_closed["symbol"] = ""
    for (k2, v2) in tmp
        if haskey(v2, "time")
            push!(timestamps, datetime2unix(DateTime(v2["time"])))
        elseif haskey(v2, "updateTime")
            push!(timestamps, v2["updateTime"]/1000)
        else
            @info("no valid timestamp")
            push!(timestamps, datetime2unix(now()))
        end
        buy_sign = 1
        if v2["side"] == "BUY"
            new_closed["buys_exec"] += 1
            buy_sign = -1
        end
        if !haskey(v2, "trades")
            sleep(0.3)
            trades = client.get_my_trades(symbol=v2["symbol"], orderId=v2["orderId"])
            v2["trades"] = trades
            v2 = add_fees_to_closed_order(v2, config, "", client)
        else
            trades = v2["trades"]
        end
        
        for t in v2["trades"]
            new_closed["symbol"] = t["symbol"]
            #
            ## should be deprecated
#             commission = typeof(t["commission"]) == Float64 ? t["commission"] : parse(Float64, t["commission"])
#             if !haskey(t, "com")
#                 if commission != 0
#                     if t["commissionAsset"] == config["farm_coin"]
#                         commission *= parse(Float64, t["price"])
#                     elseif t["commissionAsset"] != config["base_coin"]
#                         translator = string(t["commissionAsset"], config["base_coin"])
#                         #
#                         # Switch to historical data !!!
#                         #
#         #                                 commission *= parse(Float64, client.get_ticker(symbol=translator)["weightedAvgPrice"])
#                         weightedAvgPrice = try client.get_ticker(symbol=translator)["weightedAvgPrice"]
#                         catch 
#                             string(1/parse(Float64, client.get_ticker(symbol=string(config["farm_coin"], t["commissionAsset"]))["weightedAvgPrice"]))   
#                         end
#                         if typeof(weightedAvgPrice) == String
#                             weightedAvgPrice = parse(Float64, weightedAvgPrice)
#                         end
#                         println(weightedAvgPrice, " -- ", typeof(weightedAvgPrice))
#                         commission *= weightedAvgPrice
#                     end
#                 end
#             else
                
#             end
            ##
            #
            commission = typeof(t["com"]) == Float64 ? t["com"] : parse(Float64, t["com"])
            tmp_pro += buy_sign * parse(Float64, t["quoteQty"])
            tmp_pro -= commission
            new_closed["commission"] += commission
            tmp_vol += parse(Float64, t["qty"])
        end
    end

    new_closed["duration"]       = datetime2unix(unix2datetime(maximum(timestamps))) - datetime2unix(DateTime(split(id_str, "--")[end]))
    new_closed["trigger"]        = split(id_str, "--")[1]
    new_closed["profit"]         = tmp_pro
    new_closed["profit_percent"] = tmp_pro * 100 / status["volume"]
    new_closed["profit_thes"]    = tmp_pro * config["thes_factor"]
    new_closed["sell_time"]      = string(unix2datetime(maximum(timestamps)))
    
    #
    ## If base coin is NOT EUR
    if config["base_coin"] != "EUR"
        translator = string(config["base_coin"], "EUR")
        @info(translator)
        if weightedAvgTranslator == 0
            weightedAvgPrice = client.get_ticker(symbol=translator)["weightedAvgPrice"]
            if typeof(weightedAvgPrice) == String
                weightedAvgPrice = parse(Float64, weightedAvgPrice)
            end
        else
             weightedAvgPrice = weightedAvgTranslator
        end
        @info(typeof(weightedAvgPrice))
        @info(weightedAvgPrice)
        @info(new_closed["profit"])
        new_closed["weightedAvgPrice"] = weightedAvgPrice
        new_closed["profit_EUR"] = new_closed["profit"] * weightedAvgPrice
    else
        new_closed["profit_EUR"] = new_closed["profit"]
    end
    return new_closed, sell_date, yr, M, d, tmp_vol, tmp_pro
end
export determine_closed