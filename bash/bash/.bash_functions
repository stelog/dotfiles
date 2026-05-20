function sst() {
    ssh -t $@ "tmux attach || tmux";
}
