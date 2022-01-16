function get_users()
    active_users = []
    user_paths = glob(joinpath(Pinguu.base_dir[2:end], "users/*"));
    for path in user_paths
        push!(active_users, split(path, "/")[end])
    end
    user_paths = glob(joinpath(Pinguu.base_dir[2:end], "invest/users/*"));
    for path in user_paths
        push!(active_users, split(path, "/")[end])
    end
    return unique(active_users)
end
return get_users