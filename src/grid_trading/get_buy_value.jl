function get_buy_value(config, trade_grid)
    cQty  = typeof(config["init_state"]["cummulativeQuoteQty"]) != Float64 ? parse(Float64, config["init_state"]["cummulativeQuoteQty"]) : config["init_state"]["cummulativeQuoteQty"]
    tQty  = typeof(config["total_value"]) != Float64 ? parse(Float64, config["total_value"]) : config["total_value"]
    
    total_range = typeof(config["grid"]["total_range"]) != Float64 ? parse(Float64, config["grid"]["total_range"]) : config["grid"]["total_range"]
    grid_step   = typeof(config["grid"]["step"]) != Float64 ? parse(Float64, config["grid"]["step"]) : config["grid"]["step"]

    total_steps =  total_range / grid_step
    sell_step_num = floor(total_steps * (cQty / tQty))
    buy_step_num  = floor(total_steps * (1 - cQty / tQty))

    current_volume_diff = Pinguu.get_current_volume(config) - tQty

    buy_coins  = tQty - cQty
    buy_step_val  = round((buy_coins  / buy_step_num) + (current_volume_diff/length(trade_grid)), digits=config["precision"])
    return buy_step_val
end
export get_buy_value