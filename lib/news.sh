# shellcheck shell=bash
# cmaal: Arch Linux news
# Part of cmaal, sourced by /usr/bin/cmaal. https://github.com/archlinux-dev/cmaal

# ---------------------------------------------------------------------------
# Arch news
# ---------------------------------------------------------------------------
NEWS_URL="https://archlinux.org/feeds/news/"

# news_items N -> "date<TAB>title<TAB>link" lines, newest first
news_items() {
    local n=${1:-5} feed
    feed=$(curl -fsSL --max-time 10 "$NEWS_URL" 2>/dev/null) || return 1
    { tr -d '\n\r' <<<"$feed"; printf '\n'; } | sed 's/<item>/\n<item>/g' | tail -n +2 | head -n "$n" | while IFS= read -r item; do
        local title date link
        title=$(sed -n 's:.*<title>\([^<]*\)</title>.*:\1:p' <<<"$item")
        date=$(sed -n 's:.*<pubDate>\([^<]*\)</pubDate>.*:\1:p' <<<"$item")
        link=$(sed -n 's:.*<link>\([^<]*\)</link>.*:\1:p' <<<"$item")
        title=$(sed -e 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&amp;/\&/g' <<<"$title")
        date=$(date -d "$date" +%Y-%m-%d 2>/dev/null || printf '%s' "$date")
        printf '%s\t%s\t%s\n' "$date" "$title" "$link"
    done
}

cmd_news() {
    local n=${1:-5} line
    [[ $n =~ ^[0-9]+$ ]] || die "usage: cmaal news [count]"
    local -a items=()
    mapfile -t items < <(news_items "$n")
    (( ${#items[@]} )) || die "could not fetch Arch news"
    section "Arch Linux news"
    for line in "${items[@]}"; do
        IFS=$'\t' read -r d title l <<<"$line"
        printf '   %s%s%s  %s%s%s\n      %s%s%s\n' "$C_DIM" "$d" "$C_RESET" "$C_BOLD" "$title" "$C_RESET" "$C_DIM" "$l" "$C_RESET"
    done
    mkdir -p "$CACHE_DIR"
    printf '%s\n' "${items[0]}" | cut -f2 >"$CACHE_DIR/news_seen"
}

# Shows news posted since the last time we looked. Returns 1 if the user aborts.
# unread_news -> news lines newer than the last one you saw (does not mark them)
unread_news() {
    local seen="" line
    local -a items=()
    [[ -f $CACHE_DIR/news_seen ]] && seen=$(<"$CACHE_DIR/news_seen")
    [[ -n $seen ]] || return 0
    mapfile -t items < <(news_items 5)
    for line in "${items[@]}"; do
        [[ $(cut -f2 <<<"$line") == "$seen" ]] && break
        printf '%s\n' "$line"
    done
}

mark_news_seen() {
    local newest
    newest=$(news_items 1 | cut -f2)
    [[ -n $newest ]] || return 0
    mkdir -p "$CACHE_DIR"
    printf '%s\n' "$newest" >"$CACHE_DIR/news_seen"
}

# Shows news posted since the last time we looked. Returns 1 if the user aborts.
check_news_before_upgrade() {
    [[ $SHOW_NEWS_ON_UPGRADE == yes ]] && have curl || return 0
    local line d title l first=""
    local -a unread=()
    [[ -f $CACHE_DIR/news_seen ]] || first=1
    mapfile -t unread < <(unread_news)
    mark_news_seen
    # first run: remember the newest item quietly
    [[ -z $first ]] || return 0
    (( ${#unread[@]} )) || return 0
    section "Unread Arch news (read before upgrading!)"
    for line in "${unread[@]}"; do
        IFS=$'\t' read -r d title l <<<"$line"
        printf '   %s%s%s  %s%s%s\n      %s\n' "$C_DIM" "$d" "$C_RESET" "$C_YELLOW$C_BOLD" "$title" "$C_RESET" "$l"
    done
    printf '\n'
    ask "Continue with the upgrade?" y
}
