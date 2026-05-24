# Por que criei uma biblioteca open-source para envio de e-mail com Cloudflare — e o que isso diz sobre o custo invisível da infraestrutura moderna

Nos últimos anos, consolidei praticamente toda a infraestrutura dos meus projetos na Cloudflare: DNS, CDN, proteção DDoS, túneis, armazenamento com R2, Workers para edge computing. Cada serviço resolvendo um problema específico, tudo dentro de um único painel, uma única fatura.

Aí chegou a hora de configurar envio de e-mail transacional.

E eu me vi prestes a contratar mais um serviço separado.

---

## O problema que ninguém fala abertamente

E-mail transacional parece simples. Na prática, é onde vários projetos pagam caro sem perceber.

Resend, Postmark, Mailgun, SendGrid — todos excelentes. Mas todos compartilham o mesmo modelo de negócio: plano gratuito com **limite de ~100 e-mails por dia**, e a partir do momento que você precisa de mais, o primeiro tier pago começa na faixa de **$20/mês** — antes de você ter gerado um centavo de receita com o projeto.

Quando a Cloudflare anunciou o **Email Service**, a conta foi imediata:

| | Provedores tradicionais | Cloudflare Email Service |
|---|---|---|
| Plano gratuito | ~100 e-mails/dia | Somente endereços verificados |
| Plano pago | A partir de $20/mês | **$5/mês** (Workers) |
| Limite diário pago | Varia por plano | **1.000 e-mails/dia** |
| Cap mensal | Depende do plano | Não publicado |
| Domínio próprio | Configuração separada | Já está na Cloudflare |

1.000 e-mails/dia cobre com folga a maioria dos SaaS em fase inicial e muitos em crescimento — e o plano já existe para quem usa Workers por qualquer outro motivo.

Não é só sobre preço. É sobre **não precisar de mais um cartão de crédito, mais um contrato, mais um painel**.

---

## O sinal que confirmou que era hora de apostar

O Cloudflare Email Service ainda está tecnicamente em beta. Mas um detalhe me chamou atenção: o **Laravel** — um dos frameworks PHP mais usados no mundo, com dezenas de milhões de instalações — começou a adicionar suporte nativo ao serviço.

Frameworks mainstream não integram APIs instáveis. Esse foi o sinal que precisava.

---

## O gap no ecossistema Elixir

Meus projetos são construídos em **Elixir com Phoenix**. O envio de e-mail no ecossistema Elixir passa pelo **Swoosh** — uma biblioteca elegante que padroniza a interface de envio e suporta dezenas de provedores via adapters intercambiáveis: Resend, Postmark, Mailgun, Sendgrid e outros.

Pesquisei no Hex.pm (o repositório de pacotes Elixir): nenhum adapter Swoosh para Cloudflare Email existia.

Então criei.

---

## swoosh_cloudflare

Publiquei o `swoosh_cloudflare` — um adapter Swoosh que conecta qualquer aplicação Phoenix ao Cloudflare Email Service via REST API.

A configuração:

```elixir
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Cloudflare,
  api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID")
```

O envio segue o padrão Swoosh que qualquer developer Elixir já conhece:

```elixir
new()
|> to({"Alice", "alice@example.com"})
|> from({"My App", "noreply@seudominio.com"})
|> subject("Bem-vindo!")
|> html_body("<h1>Olá, Alice!</h1>")
|> MyApp.Mailer.deliver()
```

Suporta anexos, cc/bcc, reply-to, tratamento estruturado de erros com os códigos da API Cloudflare, timeout configurado e envio paralelo via `deliver_many/2`.

---

## O que aprendi com isso

Infraestrutura fragmentada tem um custo real — não só financeiro, mas cognitivo. Cada serviço separado é mais um painel, mais uma chave de API para rotacionar, mais um contrato para cancelar se o projeto não decolar.

Consolidar dentro da Cloudflare não é só sobre economizar $15/mês. É sobre reduzir a superfície de complexidade operacional enquanto o projeto ainda está crescendo.

E quando você resolve um problema assim e percebe que mais ninguém no seu ecossistema resolveu antes, publicar como open-source leva menos tempo do que parece — e deixa a solução disponível para quem vier depois.

---

📦 Pacote no Hex.pm: [swoosh_cloudflare](https://hex.pm/packages/swoosh_cloudflare)
🔗 Código no GitHub: [devaction-labs/swoosh_cloudflare](https://github.com/devaction-labs/swoosh_cloudflare)
📄 Cloudflare Email Service: [developers.cloudflare.com/email-service](https://developers.cloudflare.com/email-service/)

Se você usa Elixir + Phoenix e já tem domínios na Cloudflare, vale conferir.

---

*Você já consolidou infra em um único provedor? Qual foi o maior ganho prático? Deixa nos comentários.*

---

## Notas para postagem

**Hashtags:** `#elixir` `#opensource` `#cloudflare` `#saas` `#hexpm` `#desenvolvimentoweb` `#phoenixframework`

**Dica:** Adicione uma imagem de capa com o logo do Cloudflare + o símbolo do Elixir (drop laranja) — chama atenção no feed antes do texto.
