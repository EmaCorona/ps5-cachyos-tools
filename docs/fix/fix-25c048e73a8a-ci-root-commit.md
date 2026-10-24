# Fallback CI per il commit radice

## Problema

Il controllo whitespace della CI ricostruiva l'albero vuoto per un branch con commit radice, ma lo validava come se fosse un commit Git. Questo interrompeva la pipeline prima di eseguire il diff.

## Correzione applicata

La pipeline distingue l'albero vuoto dai commit e applica `git diff --check` direttamente tra l'albero vuoto e l'head. I push ordinari e le pull request continuano a usare i riferimenti effettivi di base e head.

## Verifica e limiti

La sintassi dello workflow è inclusa nei controlli locali; il comportamento remoto deve essere osservato su GitHub Actions.

Commit: [`25c048e73a8ae19e6cd5a8d61a5b77f14cedc2e9`](https://github.com/EmaCorona/ps5-cachyos-tools/commit/25c048e73a8ae19e6cd5a8d61a5b77f14cedc2e9).
