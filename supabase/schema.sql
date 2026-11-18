-- Schema derivado dos nós Supabase/Postgres dos workflows.
-- Rodar no SQL Editor do Supabase antes de importar os workflows.

create extension if not exists vector;

-- Uma linha por conversa (telefone). Usada para saber se o contato é novo.
create table if not exists chats (
  id          bigint generated always as identity primary key,
  phone       text not null unique,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Histórico legível de cada troca (mensagem do lead + resposta do agente).
-- Fonte para a extração de dados do lead, para a nutrição e para a revisão diária.
create table if not exists chat_messages (
  id            bigint generated always as identity primary key,
  phone         text not null,
  nomewpp       text,
  email         text,
  user_message  text,
  bot_message   text,
  message_type  text,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists chat_messages_phone_idx on chat_messages (phone, created_at);

-- Estado do lead: dados qualificados, pausa da IA e passo de nutrição.
create table if not exists dados_cliente (
  id                     bigint generated always as identity primary key,
  telefone               text not null unique,
  nome                   text,
  interesse              text,
  tipo_imovel            text,
  regiao                 text,
  faixa_valor            text,
  email                  text,
  atendimento_ia         text,             -- 'pause' quando um humano assumiu; 'reativada' ao devolver
  nurturing_step         integer not null default 0,  -- 0 = fora da sequência; 1..3 = próximo passo
  nurturing_enrolled_at  timestamptz,
  created_at             timestamptz not null default now()
);
create index if not exists dados_cliente_nurturing_idx on dados_cliente (nurturing_step) where nurturing_step <> 0;

-- Memória de conversa do agente (nó Postgres Chat Memory).
-- O n8n cria esta tabela sozinho na primeira execução; está aqui para o schema ficar completo.
create table if not exists n8n_chat_histories (
  id          serial primary key,
  session_id  varchar(255) not null,
  message     jsonb not null,
  created_at  timestamptz not null default now()
);
create index if not exists n8n_chat_histories_session_idx on n8n_chat_histories (session_id);

-- Base de conhecimento vetorial (Supabase Vector Store).
-- 1536 dimensões = text-embedding-3-small.
create table if not exists documents (
  id         bigserial primary key,
  content    text,
  metadata   jsonb,
  embedding  vector(1536)
);

create or replace function match_documents (
  query_embedding vector(1536),
  match_count int default null,
  filter jsonb default '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    documents.id,
    documents.content,
    documents.metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where documents.metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;
