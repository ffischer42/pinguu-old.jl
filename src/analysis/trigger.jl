function get_trigger_limits(config_paths)
    triggers = Dict()
    triggers["BUY"] = Dict()
    triggers["SELL"] = Dict()
    for (symbol, paths) in config_paths
        !haskey(triggers["BUY"],  symbol) ? triggers["BUY"][symbol]  = Dict() : ""
        !haskey(triggers["SELL"], symbol) ? triggers["SELL"][symbol] = Dict() : ""
        for bot_path in paths
            open_orders = JSON.parsefile(joinpath(bot_path, "open_orders.json"))
            for (k,v) in open_orders["BUY"]
                if !haskey(triggers["BUY"][symbol], bot_path)
                    if haskey(v, "price")
                        triggers["BUY"][symbol][bot_path] = parse(Float64, v["price"])
                    end
                else
                    if parse(Float64, v["price"]) < triggers["BUY"][symbol][bot_path]
                        if haskey(v, "price")
                            triggers["BUY"][symbol][bot_path] = parse(Float64, v["price"])
                        end
                    end
                end
            end
            for (k,v) in open_orders["SELL"]
                if !haskey(triggers["SELL"][symbol], bot_path)
                    if haskey(v, "price")
                        triggers["SELL"][symbol][bot_path] = parse(Float64, v["price"])
                    end
                else
                    if parse(Float64, v["price"]) < triggers["SELL"][symbol][bot_path]
                        if haskey(v, "price")
                            triggers["BUY"][symbol][bot_path] = parse(Float64, v["price"])
                        end
                    end
                end
            end
        end
    end
    return triggers
end
function place_triggers(config_paths, symbol, price)
    if typeof(price) == String
        price = parse(Float64, price)
    end
    triggers = get_trigger_limits(config_paths)
    if haskey(triggers["SELL"], symbol)
        for (k,v) in triggers["SELL"][symbol]
            if v * 0.9985 <= price
                if !isfile(joinpath(k, "trigger.json"))
                    open(joinpath(k, "trigger.json"), "w") do f
                        JSON.print(f, Dict(), 4)
                    end
                end
            end
        end
    end
    if haskey(triggers["BUY"], symbol)
        for (k,v) in triggers["BUY"][symbol]
            if v * 1.0015 >= price
                if !isfile(joinpath(k, "trigger.json"))
                    open(joinpath(k, "trigger.json"), "w") do f
                        JSON.print(f, Dict(), 4)
                    end
                end
            end
        end
    end
end