# Por que criei uma biblioteca open-source para envio de e-mail com Cloudflare — e o que isso diz sobre o custo invisível da infraestrutura moderna

Nos últimos anos, consolidei praticamente toda a infraestrutura dos meus projetos na Cloudflare: DNS, CDN, proteção DDoS, túneis, armazenamento com R2, Workers para edge computing. Cada serviço resolvendo um problema específico, tudo dentro de um único painel, uma única fatura.

Aí chegou a hora de configurar envio de e-mail transacional.

E eu me vi prestes a contratar mais um serviço separado.

---

## O problema que ninguém fala abertamente

E-mail transacional parece simples. Na prática, é onde vários projetos pagam caro sem perceber.

Resend, Postmark, Mailgun, SendGrid — todos excelentes. Mas todos têm algo em comum: o plano gratuito é apertado, e o primeiro tier pago começa na faixa de **$20/mês**. Para projetos em fase inicial ou pequenos SaaS, esse custo existe antes de você enviar o primeiro e-mail de produção que gera receita.

Quando a Cloudflare anunciou o **Email Service** — um serviço de envio de e-mail transacional via REST API integrado à conta onde seus domínios já estão — a conta foi imediata: **$5/mês pelo plano Workers**, sem custo adicional pelo envio de e-mail, usando os domínios que eu já tinha configurados lá.

---

## O sinal que confirmou que era hora de apostar

O Cloudflare Email Service ainda está tecnicamente em beta. Mas um detalhe me chamou atenção: o **Laravel** — um dos frameworks PHP mais usados no mundo, com milhões de instalações — começou a adicionar suporte nativo ao serviço.

Frameworks mainstream não integram APIs instáveis. Esse foi o sinal que precisava.

---

## O gap no ecossistema Elixir

Meus projetos são construídos em **Elixir com Phoenix**. O envio de e-mail no ecossistema Elixir passa pelo **Swoosh** — uma biblioteca elegante que padroniza a interface de envio e suporta dezenas de provedores via adapters intercambiáveis.

Pesquisei no Hex.pm (o repositório de pacotes do Elixir): nenhum adapter Swoosh para Cloudflare Email existia.

Então criei.

---

## swoosh_cloudflare

Em algumas horas de trabalho, publiquei o `swoosh_cloudflare` — um adapter Swoosh que conecta qualquer aplicação Phoenix ao Cloudflare Email Service via REST API.

A configuração é essa:

```elixir
config :my_app, MyApp.Mailer,
  adapter: Swoosh.Adapters.Cloudflare,
  api_token: System.get_env("CLOUDFLARE_EMAIL_TOKEN"),
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID")
```

E o envio segue o padrão Swoosh que qualquer developer Elixir já conhece:

```elixir
new()
|> to({"Alice", "alice@example.com"})
|> from({"My App", "noreply@seudominio.com"})
|> subject("Bem-vindo!")
|> html_body("<h1>Olá, Alice!</h1>")
|> MyApp.Mailer.deliver()
```

Suporta anexos, cc/bcc, reply-to, tratamento estruturado de erros com os códigos da API Cloudflare, timeout configurado e envio paralelo de múltiplos e-mails via `deliver_many/2`.

---

## O que aprendi com isso

Infraestrutura fragmentada tem um custo real — não só financeiro, mas cognitivo. Cada serviço separado é mais um painel, mais um cartão de crédito, mais uma chave de API para rotacionar, mais um contrato para cancelar se o projeto não decolar.

Consolidar dentro da Cloudflare não é só sobre economizar $15/mês. É sobre reduzir a superfície de complexidade operacional enquanto o projeto ainda está crescendo.

E quando você resolve um problema assim e percebe que mais ninguém no seu ecossistema resolveu antes, publicar como open-source leva menos tempo do que parece — e deixa a solução disponível para quem vier depois.

---

📦 Pacote no Hex.pm: [swoosh_cloudflare](https://hex.pm/packages/swoosh_cloudflare)
🔗 Código no GitHub: [devaction-labs/swoosh_cloudflare](https://github.com/devaction-labs/swoosh_cloudflare)
📄 Documentação Cloudflare Email Service: [developers.cloudflare.com/email-service](https://developers.cloudflare.com/email-service/)

Se você usa Elixir + Phoenix e já tem domínios na Cloudflare, vale conferir.

---

*Você já consolidou infra em um único provedor? Qual foi o maior ganho prático? Deixa nos comentários.*

---

## Notas para postagem

**Hashtags:** `#elixir` `#opensource` `#cloudflare` `#saas` `#hexpm` `#desenvolvimentoweb` `#phoenixframework`

**Dica:** Adicione uma imagem de capa com o logo do Cloudflare + o símbolo do Elixir (drop laranja) — chama atenção no feed antes do texto.
