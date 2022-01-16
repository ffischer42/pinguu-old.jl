function get_total_bot_volume(u::String="*")
    vol = 0
    #
    ## Pinguus
    config_paths = glob(joinpath(Pinguu.base_dir, "users/" * u * "/*/config.json"));
    for path in config_paths
        tmp = JSON.parsefile(path)
        if tmp["status"] != "dead"
            if tmp["base_coin"] == "EUR"
                for (k,v) in tmp["volume"]
                    vol += v
                end
                vol += tmp["thes_vol"]
            else
                translator = tmp["base_coin"] * "EUR"
                ticker = JSON.parsefile(joinpath(Pinguu.base_dir, "ticker/" * translator * "_kline_1m_graph.json"))
                price = ticker["price"][end]
                for (k,v) in tmp["volume"]
                    vol += v * price
                end
                vol += tmp["thes_vol"] * price
            end
        end
    end
    #
    ## Grid bots
    config_paths = glob(joinpath(Pinguu.base_dir, "grid_bots/user/" * u * "/*/config.json"));
    for path in config_paths
        tmp = JSON.parsefile(path)
        if tmp["testing"] == "0" && tmp["status"] != "finished"
            vol += Pinguu.get_current_volume(tmp)
        end
    end
    return vol
end
export get_total_bot_volume