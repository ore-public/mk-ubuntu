#
# 全ての zsh が最初に読むファイル。/etc/skel から新規ユーザーへ配布される。
#

# Ubuntu の /etc/zsh/zshrc は、この変数が空のときに compinit を実行する。
# zimfw の completion モジュールが後から compinit を呼び直すことになり、
# 「completion was already initialized before completion module」という
# 警告が毎回出るため、システム側の compinit を止めて zimfw に任せる。
skip_global_compinit=1
