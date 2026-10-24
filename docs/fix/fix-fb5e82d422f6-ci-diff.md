# Verifica whitespace sul diff effettivo

## Problema

`git diff --check` eseguito dopo un checkout pulito non analizzava necessariamente le modifiche del push o della pull request.

## Correzione applicata

La CI usa `fetch-depth: 0` e confronta esplicitamente `github.event.before` con `github.sha` sui push, oppure la base e l'head della pull request. Per il primo commit ricostruisce una base valida dall'albero vuoto o dal genitore disponibile.

## Verifica e limiti

La sintassi del workflow e il controllo locale su staging passano. L'esecuzione remota dei casi GitHub Actions dipende dal servizio CI e deve essere osservata sul branch pushato.

Commit: [`fb5e82d422f6345f7a5063b28ad7db6432e6d481`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/fb5e82d422f6345f7a5063b28ad7db6432e6d481).
