function load_past_months(bot_path; num=2)
    base_dir = joinpath(bot_path, "closed_orders/")
    months = []
    orders = Dict()
    for i in 0:1:num-1
        day = string(today() - Month(i))
        file = joinpath(joinpath(base_dir, split(day, "-")[1]), split(day, "-")[2]) * ".json"
        if isfile(file)
            tmp = JSON.parsefile(file)
            for (k,v) in tmp
                if !(k in ["profit", "trade_num"])
                    for (k1,v1) in v["trades"]
                        orders[k1] =  v1["orders"]
                    end
                end
            end
        end
    end
    return orders
end
export load_past_months