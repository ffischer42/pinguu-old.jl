function calc_order_fee(client, trades, config)
    com = 0
    for t in trades
        commission = typeof(t["commission"]) == Float64 ? t["commission"] : parse(Float64, t["commission"])
        if commission != 0
            if t["commissionAsset"] == config["farm_coin"]
                commission *= parse(Float64, t["price"])
            elseif t["commissionAsset"] != config["base_coin"]
                translator = string(t["commissionAsset"], config["base_coin"])
                weightedAvgPrice = try client.get_ticker(symbol=translator)["weightedAvgPrice"]
                catch 
                    string(1/parse(Float64, client.get_ticker(symbol=string(config["farm_coin"], t["commissionAsset"]))["weightedAvgPrice"]))   
                end
                if typeof(weightedAvgPrice) == String
                    weightedAvgPrice = parse(Float64, weightedAvgPrice)
                end
                commission *= weightedAvgPrice
            end
        end
        com += commission
    end
    return com
end
export calc_order_fee