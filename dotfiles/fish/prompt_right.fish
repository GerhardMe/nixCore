function fish_right_prompt
    set branch (git symbolic-ref --short HEAD 2>/dev/null)

    if test -n "$branch"
        printf '\033[38;5;253m(%s)\033[0m' $branch
    end
end
