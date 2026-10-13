# bootstrap

Primeiro passo num PC zerado (Ubuntu/Zorin/Pop, Fedora, Arch, macOS):

```sh
curl -fsSL https://boot.medeiros.cloud | bash
```

Instala git/curl/ssh, cria a chave SSH, cadastra a chave no GitHub com login pelo navegador ou pelo celular, clona o repo privado `scripts` em `~/git/scripts` e entrega a vez ao `pos-install.sh`, que chama o chezmoi.

```sh
curl -fsSL https://boot.medeiros.cloud | bash -s -- --dry-run            # só mostra
curl -fsSL https://boot.medeiros.cloud | bash -s -- --only dotfiles,apps # repassa ao pos-install
curl -fsSL https://boot.medeiros.cloud | bash -s -- --bootstrap-only     # para depois do clone
```

Se a VPS estiver fora do ar, use o endereço direto:
`curl -fsSL https://raw.githubusercontent.com/allanmedeiros71/bootstrap/main/bootstrap.sh | bash`

**Repo público: nenhum segredo aqui.** O `boot.medeiros.cloud` é só um redirecionamento (ver `coolify/`).
