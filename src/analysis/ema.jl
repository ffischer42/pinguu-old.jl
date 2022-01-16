function get_ema(x; ema=[8,13,21,55])
    output = []
    for e in ema
        push!(output, Indicators.ema(float.(x), n=e))
    end
    return output    
end