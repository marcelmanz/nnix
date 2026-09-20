{pkgs}:
pkgs.writeShellApplication {
  name = "pinentry-rbw";
  runtimeInputs = with pkgs; [libsecret pinentry-qt];
  text = ''
    # auto-fills the rbw master password from the gnome login keyring
    pass=$(secret-tool lookup application rbw 2>/dev/null)
    [ -n "$pass" ] || exec pinentry-qt "$@"

    printf 'OK Pleased to meet you\n'
    while IFS= read -r line; do
      case "$line" in
        GETPIN) printf 'D %s\nOK\n' "''${pass//'%'/'%25'}" ;;
        BYE) printf 'OK\n'; exit 0 ;;
        *) printf 'OK\n' ;;
      esac
    done
  '';
  meta.mainProgram = "pinentry-rbw";
}
