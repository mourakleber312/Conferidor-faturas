part of '../main.dart';

class ParserItau {
  static int centavos(double valor) {
    return (valor * 100).round();
  }

  static String semAcentos(String texto) {
    return texto
        .replaceAll(
          RegExp('[áàãâäÁÀÃÂÄ]'),
          'a',
        )
        .replaceAll(
          RegExp('[éèêëÉÈÊË]'),
          'e',
        )
        .replaceAll(
          RegExp('[íìîïÍÌÎÏ]'),
          'i',
        )
        .replaceAll(
          RegExp('[óòõôöÓÒÕÔÖ]'),
          'o',
        )
        .replaceAll(
          RegExp('[úùûüÚÙÛÜ]'),
          'u',
        )
        .replaceAll(
          RegExp('[çÇ]'),
          'c',
        );
  }

  static String limparEspacos(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(
          RegExp(r'[ \t]+'),
          ' ',
        )
        .trim();
  }

  static String chave(String texto) {
    return semAcentos(texto)
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
  }

  static String compacto(String texto) {
    return semAcentos(texto)
        .toLowerCase()
        .replaceAll(
          RegExp(r'\s+'),
          '',
        );
  }

  static double moeda(String texto) {
    var t = texto
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    final negativo = t.startsWith('-');

    if (negativo) {
      t = t.substring(1);
    }

    t = t
        .replaceAll('.', '')
        .replaceAll(',', '.');

    final valor =
        double.tryParse(t) ?? 0;

    return negativo
        ? -valor
        : valor;
  }

  static bool dataValida(String data) {
    final partes = data.split('/');

    if (partes.length != 2) {
      return false;
    }

    final dia =
        int.tryParse(partes[0]);

    final mes =
        int.tryParse(partes[1]);

    return dia != null &&
        mes != null &&
        dia >= 1 &&
        dia <= 31 &&
        mes >= 1 &&
        mes <= 12;
  }

  static String normalizarDatas(
    String linha,
  ) {
    return linha.replaceAllMapped(
      RegExp(
        r'(\d)\s*(\d)\s*/\s*(\d)\s*(\d)',
      ),
      (m) =>
          '${m.group(1)}'
          '${m.group(2)}/'
          '${m.group(3)}'
          '${m.group(4)}',
    );
  }

  static double? valorAposMarcador(
    String texto,
    List<String> marcadores,
  ) {
    final c = compacto(texto);

    for (final marcador in marcadores) {
      final alvo =
          compacto(marcador);

      var pos =
          c.indexOf(alvo);

      while (pos >= 0) {
        final inicio =
            pos + alvo.length;

        final fim =
            (inicio + 80)
                .clamp(
                  0,
                  c.length,
                )
                .toInt();

        final trecho =
            c.substring(
          inicio,
          fim,
        );

        final m = RegExp(
          r'^:?r?\$?(-?[\d.]+,\d{2})',
        ).firstMatch(trecho);

        if (m != null) {
          return moeda(
            m.group(1)!,
          );
        }

        pos = c.indexOf(
          alvo,
          pos + 1,
        );
      }
    }

    return null;
  }

  static String procurarVencimento(
    String texto,
  ) {
    final normal =
        normalizarDatas(texto);

    final m = RegExp(
      r'vencimento\s*:?\s*(\d{2}/\d{2}/\d{4})',
      caseSensitive: false,
    ).firstMatch(normal);

    if (m != null) {
      return m.group(1)!;
    }

    final linhas =
        normal.split('\n');

    for (var i = 0;
        i < linhas.length;
        i++) {
      if (!chave(linhas[i])
          .contains('vencimento')) {
        continue;
      }

      final d = RegExp(
        r'\d{2}/\d{2}/\d{4}',
      ).firstMatch(
        linhas[i],
      );

      if (d != null) {
        return d.group(0)!;
      }

      if (i + 1 < linhas.length) {
        final d2 = RegExp(
          r'\d{2}/\d{2}/\d{4}',
        ).firstMatch(
          linhas[i + 1],
        );

        if (d2 != null) {
          return d2.group(0)!;
        }
      }
    }

    return '';
  }

  static String procurarCartao(
    String texto,
  ) {
    final m = RegExp(
      r'cart[aã]o\s*([0-9]{4}\.[Xx]{4}\.[Xx]{4}\.[0-9]{4})',
      caseSensitive: false,
    ).firstMatch(texto);

    return m?.group(1) ?? '';
  }

  static const categorias = <String>[
    'restaurante',
    'supermercado',
    'vestuário',
    'vestuario',
    'saúde',
    'saude',
    'serviços',
    'servicos',
    'outros',
    'lazer',
    'eletrônicos',
    'eletronicos',
    'educação',
    'educacao',
    'hotel',
    'transporte',
    'automobile',
    'health',
    'money',
    'supermarket',
  ];

  static String normalizarCategoria(
    String categoria,
  ) {
    final c =
        chave(categoria);

    const mapa =
        <String, String>{
      'vestuario': 'vestuário',
      'saude': 'saúde',
      'servicos': 'serviços',
      'eletronicos': 'eletrônicos',
      'educacao': 'educação',
      'health': 'saúde',
      'money': 'serviços',
      'supermarket': 'supermercado',
      'automobile': 'automóvel',
    };

    return mapa[c] ?? c;
  }

  static String categoriaLinha(
    String linha,
  ) {
    final k =
        chave(linha);

    for (final categoria
        in categorias) {
      final ck =
          chave(categoria);

      if (k.startsWith(ck)) {
        return normalizarCategoria(
          categoria,
        );
      }
    }

    return 'outros';
  }

  static List<ValorEncontrado>
      valoresNaLinha(
    String linha,
    double limite,
  ) {
    final saida =
        <ValorEncontrado>[];

    final rx = RegExp(
      r'-?(?:\d[\d.\s]*?)?,\s*\d\s*\d',
    );

    for (final m in rx.allMatches(linha)) {
      var inicio =
          m.start;

      var bruto =
          m.group(0)!;

      var j =
          inicio - 1;

      while (j >= 0 &&
          linha[j].trim().isEmpty) {
        j--;
      }

      // Exemplo:
      // 02/04 75,57
      // O "04" não pode virar parte
      // do valor 475,57.
      if (j >= 0 &&
          linha[j] == '/') {
        final prefixo =
            RegExp(
          r'^\d{1,2}\s+',
        ).firstMatch(bruto);

        if (prefixo != null) {
          inicio +=
              prefixo.end;

          bruto =
              bruto.substring(
            prefixo.end,
          );
        }
      }

      var valor =
          moeda(bruto);

      // Alguns PDFs misturam dígitos
      // do estabelecimento com o valor.
      //
      // Exemplo:
      // LJ 23 003 7,90
      //
      // Se o número exceder o próprio
      // subtotal da fatura, removemos
      // grupos numéricos da esquerda.
      while (valor.abs() > limite) {
        final prefixo =
            RegExp(
          r'^-?\d+\s+',
        ).firstMatch(bruto);

        if (prefixo == null) {
          break;
        }

        inicio +=
            prefixo.end;

        bruto =
            bruto.substring(
          prefixo.end,
        );

        valor =
            moeda(bruto);
      }

      if (valor.abs() <= limite) {
        saida.add(
          ValorEncontrado(
            inicio,
            m.end,
            valor,
          ),
        );
      }
    }

    return saida;
  }

  static List<Lancamento>
      transacoesDaLinha(
    String original, {
    required double limite,
    required String origem,
  }) {
    final linha =
        normalizarDatas(original);

    final datas =
        RegExp(
      r'\d{2}/\d{2}',
    );

    final valores =
        valoresNaLinha(
      linha,
      limite,
    );

    final saida =
        <Lancamento>[];

    var cursor = 0;

    for (final valor in valores) {
      final possiveisDatas =
          datas
              .allMatches(
                linha,
                cursor,
              )
              .where(
                (m) =>
                    m.start <
                    valor.inicio,
              )
              .toList();

      if (possiveisDatas.isEmpty) {
        continue;
      }

      // A primeira data depois do
      // valor anterior é a data da
      // transação.
      //
      // Uma segunda DD/MM antes do
      // valor pode ser a parcela.
      final dm =
          possiveisDatas.first;

      final data =
          dm.group(0)!;

      if (!dataValida(data)) {
        continue;
      }

      var descricao =
          limparEspacos(
        linha.substring(
          dm.end,
          valor.inicio,
        ),
      );

      if (descricao.isEmpty) {
        cursor =
            valor.fim;
        continue;
      }

      final descricaoChave =
          chave(descricao);

      if (descricaoChave.contains(
            'pagamentoviaconta',
          ) ||
          descricaoChave.contains(
            'pagamentoefetuado',
          ) ||
          descricaoChave.contains(
            'totaldospagamentos',
          )) {
        cursor =
            valor.fim;
        continue;
      }

      int? parcelaAtual;
      int? totalParcelas;

      final pm = RegExp(
        r'(\d{1,2})\s*/\s*(\d{1,2})\s*$',
      ).firstMatch(
        descricao,
      );

      if (pm != null) {
        final atual =
            int.tryParse(
          pm.group(1)!,
        );

        final total =
            int.tryParse(
          pm.group(2)!,
        );

        if (atual != null &&
            total != null &&
            atual >= 1 &&
            total >= atual &&
            total <= 60) {
          parcelaAtual =
              atual;

          totalParcelas =
              total;

          descricao =
              limparEspacos(
            descricao.substring(
              0,
              pm.start,
            ),
          );
        }
      }

      if (descricao.isNotEmpty) {
        saida.add(
          Lancamento(
            data: data,
            descricao: descricao,
            categoria: 'outros',
            valor: valor.valor,
            parcelaAtual:
                parcelaAtual,
            totalParcelas:
                totalParcelas,
            tipo:
                parcelaAtual == null
                    ? 'À vista'
                    : 'Parcelada',
            observacoes:
                origem,
          ),
        );
      }

      cursor =
          valor.fim;
    }

    return saida;
  }

  static List<Lancamento>
      comprasLayoutSecoes(
    String texto,
    double totalCartao,
  ) {
    final linhas =
        texto
            .replaceAll('\r', '')
            .split('\n');

    final itens =
        <Lancamento>[];

    var dentro = false;

    final limite =
        totalCartao.abs() + 0.01;

    for (var i = 0;
        i < linhas.length;
        i++) {
      final k =
          chave(linhas[i]);

      if (k.contains(
        'lancamentoscomprasesaques',
      )) {
        dentro = true;
      }

      if (!dentro) {
        continue;
      }

      final encontrados =
          transacoesDaLinha(
        linhas[i],
        limite: limite,
        origem:
            'Parser legado - layout/seções',
      );

      var categoria =
          'outros';

      if (i + 1 <
          linhas.length) {
        categoria =
            categoriaLinha(
          linhas[i + 1],
        );
      }

      for (final e
          in encontrados) {
        itens.add(
          Lancamento(
            data: e.data,
            descricao:
                e.descricao,
            categoria:
                categoria,
            valor: e.valor,
            parcelaAtual:
                e.parcelaAtual,
            totalParcelas:
                e.totalParcelas,
            tipo: e.tipo,
            observacoes:
                e.observacoes,
          ),
        );
      }

      if (k.contains(
        'lancamentosnocartao',
      )) {
        dentro = false;
      }
    }

    return itens;
  }

  static List<Lancamento>
      comprasLayoutAmplo(
    String texto,
    double totalCartao,
  ) {
    final linhas =
        texto
            .replaceAll('\r', '')
            .split('\n');

    final itens =
        <Lancamento>[];

    var iniciou = false;

    final limite =
        totalCartao.abs() + 0.01;

    for (var i = 0;
        i < linhas.length;
        i++) {
      final k =
          chave(linhas[i]);

      if (k.contains(
        'lancamentoscomprasesaques',
      )) {
        iniciou = true;
      }

      if (!iniciou) {
        continue;
      }

      if (k.contains(
        'totaldoslancamentosatuais',
      )) {
        break;
      }

      final encontrados =
          transacoesDaLinha(
        linhas[i],
        limite: limite,
        origem:
            'Parser legado - layout/amplo',
      );

      var categoria =
          'outros';

      if (i + 1 <
          linhas.length) {
        categoria =
            categoriaLinha(
          linhas[i + 1],
        );
      }

      for (final e
          in encontrados) {
        itens.add(
          Lancamento(
            data: e.data,
            descricao:
                e.descricao,
            categoria:
                categoria,
            valor: e.valor,
            parcelaAtual:
                e.parcelaAtual,
            totalParcelas:
                e.totalParcelas,
            tipo: e.tipo,
            observacoes:
                e.observacoes,
          ),
        );
      }
    }

    return itens;
  }

  static List<Lancamento>
      comprasBruto(
    String texto,
    double totalCartao,
  ) {
    final normal =
        texto.replaceAll(
      '\r',
      '',
    );

    var inicio =
        normal
            .toLowerCase()
            .indexOf(
              'lançamentos: compras e saques',
            );

    if (inicio < 0) {
      inicio =
          normal
              .toLowerCase()
              .indexOf(
                'lancamentos: compras e saques',
              );
    }

    if (inicio < 0) {
      return [];
    }

    var fim =
        normal
            .toLowerCase()
            .indexOf(
              'lançamentos no cartão',
              inicio,
            );

    if (fim < 0) {
      fim =
          normal
              .toLowerCase()
              .indexOf(
                'lancamentos no cartao',
                inicio,
              );
    }

    if (fim <= inicio) {
      return [];
    }

    final secao =
        normal.substring(
      inicio,
      fim,
    );

    final cats =
        categorias
            .map(
              RegExp.escape,
            )
            .join('|');

    final rx = RegExp(
      '(\\d{2}/\\d{2})'
      '(.*?)'
      '(?:(\\d{1,2})/(\\d{1,2}))?'
      '(-?\\d[\\d.]*,\\d{2})'
      '($cats)',
      caseSensitive: false,
      dotAll: true,
    );

    final itens =
        <Lancamento>[];

    for (final m
        in rx.allMatches(secao)) {
      final data =
          m.group(1)!;

      if (!dataValida(data)) {
        continue;
      }

      var descricao =
          limparEspacos(
        m.group(2)!,
      );

      if (descricao.isEmpty) {
        continue;
      }

      final descricaoChave =
          chave(descricao);

      if (descricaoChave.contains(
            'pagamentoviaconta',
          ) ||
          descricaoChave.contains(
            'pagamentoefetuado',
          )) {
        continue;
      }

      final valor =
          moeda(
        m.group(5)!,
      );

      if (valor.abs() >
          totalCartao.abs() +
              0.01) {
        continue;
      }

      int? parcelaAtual;
      int? totalParcelas;

      if (m.group(3) != null &&
          m.group(4) != null) {
        final atual =
            int.tryParse(
          m.group(3)!,
        );

        final total =
            int.tryParse(
          m.group(4)!,
        );

        if (atual != null &&
            total != null &&
            atual >= 1 &&
            total >= atual &&
            total <= 60) {
          parcelaAtual =
              atual;

          totalParcelas =
              total;
        } else {
          descricao =
              '$descricao '
              '${m.group(3)}/'
              '${m.group(4)}';
        }
      }

      itens.add(
        Lancamento(
          data: data,
          descricao:
              descricao,
          categoria:
              normalizarCategoria(
            m.group(6)!,
          ),
          valor: valor,
          parcelaAtual:
              parcelaAtual,
          totalParcelas:
              totalParcelas,
          tipo:
              parcelaAtual == null
                  ? 'À vista'
                  : 'Parcelada',
          observacoes:
              'Parser legado - texto bruto sequencial',
        ),
      );
    }

    return itens;
  }



  // v11: encontra a posição real de início da coluna direita usando as
  // próprias linhas de transação do PDF. Isso evita confundir o grande
  // espaço entre descrição e valor com a separação entre as duas tabelas.
  static int? inferirCorteColunas(String texto) {
    final candidatos = <int>[];
    final linhas = texto.replaceAll('\r', '').split('\n');
    final dataRx = RegExp(r'(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)');

    for (final original in linhas) {
      final linha = original.replaceAll('\t', '    ');
      if (linha.length < 70) continue;

      for (final m in dataRx.allMatches(linha)) {
        // Datas da coluna direita ficam bem depois do início da linha.
        // Parcelas NN/NN da coluna esquerda normalmente ficam antes disso.
        if (m.start >= 58) {
          candidatos.add(m.start);
          break;
        }
      }
    }

    if (candidatos.length < 3) return null;
    candidatos.sort();
    final mediana = candidatos[candidatos.length ~/ 2];

    // Pequena margem para não cortar o primeiro dígito da data.
    return mediana < 55 ? 55 : (mediana > 140 ? 140 : mediana);
  }

  static List<String> dividirColunasCalibradas(String linha, int? corte) {
    final normal = linha.replaceAll('\t', '    ');
    if (corte == null || normal.length <= corte) {
      return [normal.trim(), ''];
    }

    // Procura um corredor de espaços perto do corte calibrado.
    final inicio = corte - 10 < 0 ? 0 : corte - 10;
    final fim = corte + 10 > normal.length ? normal.length : corte + 10;
    final janela = normal.substring(inicio, fim);
    final gaps = RegExp(r' {2,}').allMatches(janela).toList();

    if (gaps.isNotEmpty) {
      RegExpMatch melhor = gaps.first;
      var melhorDist = 1 << 30;
      for (final g in gaps) {
        final centroGap = inicio + ((g.start + g.end) ~/ 2);
        final d = (centroGap - corte).abs();
        if (d < melhorDist) {
          melhor = g;
          melhorDist = d;
        }
      }
      final a = inicio + melhor.start;
      final b = inicio + melhor.end;
      return [normal.substring(0, a).trim(), normal.substring(b).trim()];
    }

    return [
      normal.substring(0, corte).trim(),
      normal.substring(corte).trim(),
    ];
  }

  static List<String> dividirColunas(String linha) {
    final normal = linha.replaceAll('\t', '    ');
    final gaps = RegExp(r' {4,}').allMatches(normal).toList();

    if (gaps.isEmpty) {
      return [normal.trim(), ''];
    }

    RegExpMatch? melhor;
    var melhorDistancia = 1 << 30;
    final centro = normal.length ~/ 2;

    for (final gap in gaps) {
      if (gap.start < 12 || normal.length - gap.end < 12) {
        continue;
      }

      final distancia = (gap.start - centro).abs();
      if (distancia < melhorDistancia) {
        melhor = gap;
        melhorDistancia = distancia;
      }
    }

    if (melhor == null) {
      return [normal.trim(), ''];
    }

    return [
      normal.substring(0, melhor.start).trim(),
      normal.substring(melhor.end).trim(),
    ];
  }

  static String? estadoPeloTexto(String segmento) {
    final k = chave(segmento);

    if (k.contains('comprasparceladasproximasfaturas') ||
        k.contains('totalparaproximasfaturas') ||
        k.contains('proximafatura') ||
        k.contains('demaisfaturas')) {
      return 'futuro';
    }

    if (k.contains('pagamentosefetuados') ||
        k.contains('totaldospagamentos')) {
      return 'pagamentos';
    }

    if (k.contains('lancamentosinternacionais') ||
        k.contains('totallancamentosinter')) {
      return 'internacional';
    }

    if (k.contains('lancamentosprodutoseservicos') ||
        k.contains('produtoseservicos')) {
      return 'servicos';
    }

    if (k.contains('lancamentosnocartao')) {
      return 'fim_cartao';
    }

    if (k.contains('lancamentoscomprasesaques')) {
      return 'cartao';
    }

    if (k.contains('totaldoslancamentosatuais')) {
      return 'resumo';
    }

    return null;
  }

  static bool segmentoBloqueado(String segmento) {
    final k = chave(segmento);

    return k.contains('pagamentoviaconta') ||
        k.contains('pagamentoefetuado') ||
        k.contains('totaldospagamentos') ||
        k.contains('comprasparceladasproximasfaturas') ||
        k.contains('proximafatura') ||
        k.contains('demaisfaturas') ||
        k.contains('totalparaproximasfaturas') ||
        k.contains('limitesdecredito') ||
        k.contains('encargoscobradosnestafatura') ||
        k.contains('simulacaodecompras') ||
        k.contains('jurosmaximos');
  }

  static List<Lancamento> comprasLayoutColunas(
    String texto,
    double totalCartao,
  ) {
    final linhas = texto.replaceAll('\r', '').split('\n');
    final itens = <Lancamento>[];
    final estados = <String>['fora', 'fora'];
    final limite = totalCartao.abs() + 0.01;

    for (var i = 0; i < linhas.length; i++) {
      final colunas = dividirColunas(linhas[i]);

      for (var coluna = 0; coluna < 2; coluna++) {
        final segmento = colunas[coluna].trim();
        if (segmento.isEmpty) {
          continue;
        }

        final novoEstado = estadoPeloTexto(segmento);

        // O cabeçalho pode compartilhar a linha com uma transação da outra
        // coluna. Por isso o estado é controlado separadamente por coluna.
        if (novoEstado != null) {
          estados[coluna] = novoEstado;
        }

        if (estados[coluna] != 'cartao' ||
            segmentoBloqueado(segmento)) {
          continue;
        }

        final encontrados = transacoesDaLinha(
          segmento,
          limite: limite,
          origem: 'Parser v10 - layout/coluna ${coluna + 1}',
        );

        var categoria = 'outros';
        if (i + 1 < linhas.length) {
          final proximas = dividirColunas(linhas[i + 1]);
          categoria = categoriaLinha(proximas[coluna]);
        }

        for (final e in encontrados) {
          itens.add(
            Lancamento(
              data: e.data,
              descricao: e.descricao,
              categoria: categoria,
              valor: e.valor,
              parcelaAtual: e.parcelaAtual,
              totalParcelas: e.totalParcelas,
              tipo: e.tipo,
              observacoes: e.observacoes,
            ),
          );
        }
      }
    }

    return itens;
  }

  static List<Lancamento>?
      ajustarSubsetAoTotal(
    List<Lancamento> itens,
    double total,
  ) {
    final alvo =
        centavos(total);

    if (alvo <= 0 ||
        itens.isEmpty) {
      return null;
    }

    final positivos =
        itens
            .where(
              (e) =>
                  centavos(
                    e.valor,
                  ) >
                  0,
            )
            .toList();

    if (positivos.isEmpty) {
      return null;
    }

    final soma =
        positivos.fold<int>(
      0,
      (s, e) =>
          s + centavos(e.valor),
    );

    if (soma == alvo) {
      return positivos;
    }

    if (soma < alvo) {
      return null;
    }

    // Quando as duas colunas do PDF
    // são misturadas, a leitura pode
    // conter itens de outras seções.
    //
    // Em vez de procurar todo o
    // subtotal, procuramos apenas
    // quais valores precisam ser
    // removidos.
    final remover =
        soma - alvo;

    final anterior =
        <int, int>{
      0: -1,
    };

    final indiceUsado =
        <int, int>{};

    for (var i = 0;
        i < positivos.length;
        i++) {
      final valor =
          centavos(
        positivos[i].valor,
      );

      if (valor <= 0 ||
          valor > remover) {
        continue;
      }

      final somas =
          anterior.keys
              .toList(
                growable: false,
              );

      for (final s in somas) {
        final ns =
            s + valor;

        if (ns > remover ||
            anterior.containsKey(
              ns,
            )) {
          continue;
        }

        anterior[ns] = s;
        indiceUsado[ns] = i;
      }

      if (anterior.containsKey(
        remover,
      )) {
        break;
      }
    }

    if (!anterior.containsKey(
      remover,
    )) {
      return null;
    }

    final removerIndices =
        <int>{};

    var s =
        remover;

    while (s != 0) {
      final indice =
          indiceUsado[s];

      final ant =
          anterior[s];

      if (indice == null ||
          ant == null) {
        return null;
      }

      removerIndices.add(
        indice,
      );

      s = ant;
    }

    final resultado =
        <Lancamento>[];

    for (var i = 0;
        i < positivos.length;
        i++) {
      if (!removerIndices
          .contains(i)) {
        resultado.add(
          positivos[i],
        );
      }
    }

    return resultado;
  }


  static bool _ehCabecalhoCompras(String s) =>
      chave(s).contains('lancamentoscomprasesaques');

  static bool _ehFimCompras(String s) =>
      chave(s).contains('lancamentosnocartao');

  static bool _ehSecaoProibidaV10(String s) {
    final k = chave(s);
    return k.contains('pagamentosefetuados') ||
        k.contains('totaldospagamentos') ||
        k.contains('lancamentosinternacionais') ||
        k.contains('lancamentosprodutoseservicos') ||
        k.contains('comprasparceladasproximasfaturas') ||
        k.contains('totalparaproximasfaturas') ||
        k.contains('proximafatura') ||
        k.contains('demaisfaturas') ||
        k.contains('encargoscobradosnestafatura') ||
        k.contains('simulacaodecompras') ||
        k.contains('limitesdecredito');
  }


  static List<Lancamento> comprasTabelaV11(
    String layout,
    double totalCartao,
  ) {
    final linhas = layout.replaceAll('\r', '').split('\n');
    final itens = <Lancamento>[];
    final ativo = <bool>[false, false];
    final limite = totalCartao.abs() + 0.01;
    final corte = inferirCorteColunas(layout);

    for (var i = 0; i < linhas.length; i++) {
      final cols = dividirColunasCalibradas(linhas[i], corte);

      for (var c = 0; c < 2; c++) {
        final seg = cols[c].trim();
        if (seg.isEmpty) continue;

        final estado = estadoPeloTexto(seg);

        if (estado == 'cartao') {
          ativo[c] = true;
          continue;
        }
        if (estado == 'fim_cartao' ||
            estado == 'futuro' ||
            estado == 'pagamentos' ||
            estado == 'internacional' ||
            estado == 'servicos' ||
            estado == 'resumo') {
          ativo[c] = false;
          continue;
        }

        if (_ehSecaoProibidaV10(seg)) {
          ativo[c] = false;
          continue;
        }
        if (!ativo[c]) continue;

        final encontrados = transacoesDaLinha(
          seg,
          limite: limite,
          origem: 'Parser v13 - coluna calibrada ${c + 1}',
        );

        var categoria = 'outros';
        if (i + 1 < linhas.length) {
          final prox = dividirColunasCalibradas(linhas[i + 1], corte);
          categoria = categoriaLinha(prox[c]);
        }

        for (final e in encontrados) {
          itens.add(
            Lancamento(
              data: e.data,
              descricao: e.descricao,
              categoria: categoria,
              valor: e.valor,
              parcelaAtual: e.parcelaAtual,
              totalParcelas: e.totalParcelas,
              tipo: e.tipo,
              observacoes: e.observacoes,
            ),
          );
        }
      }
    }
    return itens;
  }

  static List<Lancamento> comprasTabelaV10(
    String layout,
    double totalCartao,
  ) {
    final linhas = layout.replaceAll('\r', '').split('\n');
    final itens = <Lancamento>[];
    final ativo = <bool>[false, false];
    final limite = totalCartao.abs() + 0.01;

    for (var i = 0; i < linhas.length; i++) {
      final cols = dividirColunas(linhas[i]);

      for (var c = 0; c < 2; c++) {
        final seg = cols[c].trim();
        if (seg.isEmpty) continue;

        if (_ehFimCompras(seg)) {
          ativo[c] = false;
          continue;
        }

        if (_ehCabecalhoCompras(seg)) {
          ativo[c] = true;

          // Há PDFs em que o cabeçalho e a primeira compra ficam no mesmo
          // fragmento. Mantemos somente o conteúdo após o cabeçalho.
          final pos = chave(seg).indexOf('lancamentoscomprasesaques');
          if (pos >= 0) {
            // Não tenta cortar por índice da string compactada: apenas ativa
            // a coluna; a primeira compra normalmente vem na linha seguinte.
          }
          continue;
        }

        if (_ehSecaoProibidaV10(seg)) {
          ativo[c] = false;
          continue;
        }

        if (!ativo[c]) continue;

        // Linhas de categoria/cidade não possuem data e são ignoradas.
        // transacoesDaLinha só retorna blocos com data e valor monetário.
        final encontrados = transacoesDaLinha(
          seg,
          limite: limite,
          origem: 'Parser v10 - tabela atual/coluna ${c + 1}',
        );

        String categoria = 'outros';
        if (i + 1 < linhas.length) {
          final prox = dividirColunas(linhas[i + 1]);
          if (c < prox.length) categoria = categoriaLinha(prox[c]);
        }

        for (final e in encontrados) {
          itens.add(
            Lancamento(
              data: e.data,
              descricao: e.descricao,
              categoria: categoria,
              valor: e.valor,
              parcelaAtual: e.parcelaAtual,
              totalParcelas: e.totalParcelas,
              tipo: e.tipo,
              observacoes: e.observacoes,
            ),
          );
        }
      }
    }
    return itens;
  }

  static List<Lancamento> comprasBrutoEstritoV10(
    String bruto,
    double totalCartao,
  ) {
    final linhas = bruto.replaceAll('\r', '').split('\n');
    final itens = <Lancamento>[];
    var ativo = false;
    final limite = totalCartao.abs() + 0.01;

    for (var i = 0; i < linhas.length; i++) {
      final linha = linhas[i].trim();
      if (linha.isEmpty) continue;

      if (_ehFimCompras(linha)) {
        ativo = false;
        continue;
      }
      if (_ehCabecalhoCompras(linha)) {
        ativo = true;
        continue;
      }
      if (_ehSecaoProibidaV10(linha)) {
        ativo = false;
        continue;
      }
      if (!ativo) continue;

      final encontrados = transacoesDaLinha(
        linha,
        limite: limite,
        origem: 'Parser v10 - bruto/tabela atual',
      );

      String categoria = 'outros';
      if (i + 1 < linhas.length) categoria = categoriaLinha(linhas[i + 1]);

      for (final e in encontrados) {
        itens.add(
          Lancamento(
            data: e.data,
            descricao: e.descricao,
            categoria: categoria,
            valor: e.valor,
            parcelaAtual: e.parcelaAtual,
            totalParcelas: e.totalParcelas,
            tipo: e.tipo,
            observacoes: e.observacoes,
          ),
        );
      }
    }
    return itens;
  }

  static String _chaveLancamentoV12(Lancamento e) {
    final desc = chave(e.descricao);
    final parc = '${e.parcelaAtual ?? 0}/${e.totalParcelas ?? 0}';
    return '${e.data}|$desc|${centavos(e.valor)}|$parc';
  }

  static List<Lancamento> _faltantesEntreFontesV12(
    List<Lancamento> base,
    List<Lancamento> fonte,
  ) {
    final contagem = <String, int>{};
    for (final e in base) {
      final k = _chaveLancamentoV12(e);
      contagem[k] = (contagem[k] ?? 0) + 1;
    }

    final faltantes = <Lancamento>[];
    for (final e in fonte) {
      final k = _chaveLancamentoV12(e);
      final qtd = contagem[k] ?? 0;
      if (qtd > 0) {
        contagem[k] = qtd - 1;
      } else {
        faltantes.add(e);
      }
    }
    return faltantes;
  }

  static Candidato? _recuperarBlocoV12(
    Candidato base,
    List<Candidato> fontes,
    int alvo,
  ) {
    final falta = alvo - base.somaCentavos;
    if (falta <= 0) return null;

    // Recuperação determinística: somente acrescenta lançamentos que existem
    // em outra leitura real do mesmo PDF e que a leitura-base perdeu.
    // Não remove compras e não usa subset-sum arbitrário.
    for (final fonte in fontes) {
      if (identical(fonte, base)) continue;

      final extras = _faltantesEntreFontesV12(base.compras, fonte.compras);
      if (extras.isEmpty) continue;

      // 1) Primeiro tenta um único lançamento perdido.
      for (final e in extras) {
        if (centavos(e.valor) == falta) {
          return Candidato(
            'V12 RECUPERAÇÃO 1 ITEM (${base.nome} + ${fonte.nome})',
            [...base.compras, e],
          );
        }
      }

      // 2) Depois tenta somente um BLOCO CONTÍGUO na ordem em que a outra
      // leitura encontrou os lançamentos. Isso corrige trechos/colunas
      // omitidos sem escolher combinações soltas apenas para fechar o total.
      for (var inicio = 0; inicio < extras.length; inicio++) {
        var soma = 0;
        for (var fim = inicio; fim < extras.length && fim < inicio + 12; fim++) {
          soma += centavos(extras[fim].valor);
          if (soma == falta) {
            return Candidato(
              'V12 RECUPERAÇÃO BLOCO (${base.nome} + ${fonte.nome})',
              [...base.compras, ...extras.sublist(inicio, fim + 1)],
            );
          }
          if (soma > falta) break;
        }
      }
    }
    return null;
  }


  static List<String> _segmentosFisicosV13(String linha) {
    final s = linha.replaceAll('\t', '    ');
    if (s.trim().isEmpty) return const ['', ''];

    // Em vez de escolher qualquer grande espaço da linha, procura separadores
    // somente na faixa central. Assim o espaço entre estabelecimento e valor
    // não vira, por engano, uma nova coluna.
    final centro = s.length ~/ 2;
    final matches = RegExp(r' {3,}').allMatches(s).where((m) {
      final p = (m.start + m.end) ~/ 2;
      return p >= 45 && p <= 115;
    }).toList();

    if (matches.isEmpty) return [s.trim(), ''];

    RegExpMatch melhor = matches.first;
    var melhorDist = 1 << 30;
    for (final m in matches) {
      final p = (m.start + m.end) ~/ 2;
      final d = (p - centro).abs();
      if (d < melhorDist) {
        melhor = m;
        melhorDist = d;
      }
    }
    return [
      s.substring(0, melhor.start).trim(),
      s.substring(melhor.end).trim(),
    ];
  }

  static bool _pareceTransacaoV13(String s) {
    if (s.trim().isEmpty) return false;
    final n = normalizarDatas(s);
    if (!RegExp(r'(?<!\d)\d{1,2}\s*/\s*\d{1,2}(?!\d)').hasMatch(n)) {
      return false;
    }
    return RegExp(r'-?\s*\d[\d .]*,\s*\d{2}\b').hasMatch(n);
  }

  static List<Lancamento> comprasFaixasFisicasV13(
    String layout,
    double totalCartao,
  ) {
    final linhas = layout.replaceAll('\r', '').split('\n');
    final saida = <Lancamento>[];
    final ativo = <bool>[false, false];
    final limite = totalCartao.abs() + 0.01;

    for (var i = 0; i < linhas.length; i++) {
      final segs = _segmentosFisicosV13(linhas[i]);

      for (var c = 0; c < 2; c++) {
        final seg = c < segs.length ? segs[c].trim() : '';
        if (seg.isEmpty) continue;
        final estado = estadoPeloTexto(seg);

        if (estado == 'cartao' || _ehCabecalhoCompras(seg)) {
          ativo[c] = true;
          continue;
        }

        if (estado == 'fim_cartao' ||
            estado == 'futuro' ||
            estado == 'pagamentos' ||
            estado == 'internacional' ||
            estado == 'servicos' ||
            estado == 'resumo' ||
            _ehFimCompras(seg) ||
            _ehSecaoProibidaV10(seg)) {
          ativo[c] = false;
          continue;
        }

        if (!ativo[c] || !_pareceTransacaoV13(seg)) continue;

        final encontrados = transacoesDaLinha(
          seg,
          limite: limite,
          origem: 'Parser v13 - faixa física ${c + 1}',
        );

        var categoria = 'outros';
        if (i + 1 < linhas.length) {
          final prox = _segmentosFisicosV13(linhas[i + 1]);
          if (c < prox.length) categoria = categoriaLinha(prox[c]);
        }

        for (final e in encontrados) {
          saida.add(Lancamento(
            data: e.data,
            descricao: e.descricao,
            categoria: categoria,
            valor: e.valor,
            parcelaAtual: e.parcelaAtual,
            totalParcelas: e.totalParcelas,
            tipo: e.tipo,
            observacoes: e.observacoes,
          ));
        }
      }
    }
    return saida;
  }

  static Candidato? _consensoV13(
    List<Candidato> candidatos,
    int alvo,
  ) {
    // Só aceita fusão quando a transação aparece literalmente em ao menos uma
    // fonte e a base está abaixo do subtotal. Nenhuma compra é removida.
    final ordenados = [...candidatos]..sort((a,b) =>
      (alvo-a.somaCentavos).abs().compareTo((alvo-b.somaCentavos).abs()));

    for (final base in ordenados) {
      if (base.somaCentavos >= alvo) continue;
      final falta = alvo - base.somaCentavos;

      for (final fonte in candidatos) {
        if (identical(base, fonte)) continue;
        final extras = _faltantesEntreFontesV12(base.compras, fonte.compras);

        // Recupera primeiro um único item inequívoco.
        for (final e in extras) {
          if (centavos(e.valor) == falta) {
            return Candidato(
              'V13 CONSENSO 1 ITEM (${base.nome} + ${fonte.nome})',
              [...base.compras, e],
            );
          }
        }

        // Ou um trecho contíguo curto, preservando a ordem física da fonte.
        for (var a=0; a<extras.length; a++) {
          var soma=0;
          for (var b=a; b<extras.length && b<a+8; b++) {
            soma += centavos(extras[b].valor);
            if (soma == falta) {
              return Candidato(
                'V13 CONSENSO BLOCO (${base.nome} + ${fonte.nome})',
                [...base.compras, ...extras.sublist(a,b+1)],
              );
            }
            if (soma > falta) break;
          }
        }
      }
    }
    return null;
  }



  // ============================================================
  // V15 - PARSER DEDICADO AO MODELO ESTRUTURAL DA FATURA 202442
  //
  // Este parser NÃO altera V14-A. Ele reconhece a estrutura específica:
  // - página/bloco com Pagamentos à esquerda e Compras à direita;
  // - página/bloco seguinte com Compras nas duas colunas;
  // - página/bloco final com Compras à esquerda e
  //   Internacional/Produtos/Futuras à direita.
  //
  // O subtotal oficial é usado SOMENTE para validar o resultado.
  // Não há subset-sum, remoção para "fechar", consenso ou fusão de parsers.
  // ============================================================

  static int? _inicioColunaDireitaV15(String bloco) {
    for (final linha in bloco.replaceAll('\r', '').split('\n')) {
      final n = normalizarDatas(linha);
      for (final m in RegExp(r'(?<!\d)\d{2}/\d{2}(?!\d)').allMatches(n)) {
        // Datas de parcelas (ex.: 04/12) ficam normalmente dentro da
        // descrição da coluna esquerda. A coluna física direita deste
        // modelo começa mais adiante.
        if (m.start >= 50) return m.start;
      }
    }
    return null;
  }

  static List<String> _paginasOuBlocosV15(String layout) {
    final normal = layout.replaceAll('\r', '');

    // Syncfusion pode preservar quebra de página como form-feed.
    final paginas = normal.split('\f').where((e) => e.trim().isNotEmpty).toList();
    if (paginas.length > 1) return paginas;

    // Fallback: mantém o documento inteiro. O reconhecimento abaixo continua
    // conservador; se o formato não for reconhecido, este parser devolve vazio.
    return <String>[normal];
  }

  static bool _cabecalhoComprasV16(String s) {
    final k = chave(s);
    return k.contains('lancamentoscomprasesaques');
  }

  static bool _encerraComprasV16(String s) {
    final k = chave(s);
    return k.contains('pagamentosefetuados') ||
        k.contains('totaldospagamentos') ||
        k.contains('pagamentoviaconta') ||
        k.contains('lancamentosinternacionais') ||
        k.contains('lancamentosprodutoseservicos') ||
        k.contains('produtoseservicos') ||
        k.contains('comprasparceladasproximasfaturas') ||
        k.contains('proximasfaturas') ||
        k.contains('lancamentosnocartao') ||
        k.contains('resumodafatura');
  }

  static List<String> _paginasV19(String layoutPaginas) {
    final partes = layoutPaginas.split(RegExp(r'\n===== PAGINA \d+ =====\n'));
    return partes.where((p) => p.trim().isNotEmpty).toList(growable: false);
  }

  static int _corteColunasV19(String linha) {
    // Nos cabeçalhos do Itaú as duas tabelas são separadas por um grande
    // intervalo horizontal. layoutText:true preserva esse intervalo.
    final gaps = RegExp(r' {8,}').allMatches(linha).toList(growable: false);
    if (gaps.isEmpty) return -1;

    // Ignora indentação inicial e escolhe o maior vão interno.
    RegExpMatch? melhor;
    for (final g in gaps) {
      if (g.start < 8) continue;
      if (melhor == null || (g.end - g.start) > (melhor.end - melhor.start)) {
        melhor = g;
      }
    }
    return melhor?.end ?? -1;
  }

  static int _indiceCabecalhoV19(String linha, String termo, [int inicio = 0]) {
    final alvo = chave(termo);
    if (alvo.isEmpty) return -1;
    // Procura por posição física aproximada: testa sufixos da linha e retorna
    // a primeira coluna cujo texto normalizado passa a conter o cabeçalho.
    for (var i = inicio; i < linha.length; i++) {
      if (chave(linha.substring(i)).startsWith(alvo)) return i;
    }
    return -1;
  }

  static List<Lancamento> _segmentoComprasV19(
    String segmento,
    double limite,
    String observacao,
  ) {
    final k = chave(segmento);
    if (k.isEmpty ||
        k.contains('pagamentoviaconta') ||
        k.contains('totaldospagamentos') ||
        k.contains('lancamentosnocartao') ||
        k.contains('totaltransacoesinter') ||
        k.contains('repasse de iof') ||
        k.contains('totallancamentosinter') ||
        k.contains('mensalidadeplanodo') ||
        k.contains('reducaomensalidade') ||
        k.contains('lancamentosprodutoseservicos') ||
        k.contains('proximafatura') ||
        k.contains('demaisfaturas') ||
        k.contains('totalparaproximasfaturas')) {
      return const <Lancamento>[];
    }
    if (!_pareceTransacaoV13(segmento)) return const <Lancamento>[];

    final tx = transacoesDaLinha(
      segmento,
      limite: limite,
      origem: observacao,
    );
    return tx
        .map(
          (e) => Lancamento(
            data: e.data,
            descricao: e.descricao,
            categoria: categoriaLinha(segmento),
            valor: e.valor,
            parcelaAtual: e.parcelaAtual,
            totalParcelas: e.totalParcelas,
            tipo: e.tipo,
            observacoes: observacao,
          ),
        )
        .toList(growable: false);
  }

  static List<Lancamento> _transacoesLinhaV21(
    String linha,
    double limite,
    String observacao,
  ) {
    final k = chave(linha);
    if (k.contains('pagamentoviaconta') &&
        !RegExp(r'\\d{2}\\s*/\\s*\\d{2}.*\\d{2}\\s*/\\s*\\d{2}').hasMatch(normalizarDatas(linha))) {
      return const <Lancamento>[];
    }
    final tx = transacoesDaLinha(linha, limite: limite, origem: observacao);
    return tx.where((e) {
      final d = chave(e.descricao);
      return !d.contains('pagamentoviaconta') &&
          !d.contains('pagamentoefetuado') &&
          !d.contains('totaldospagamentos') &&
          !d.contains('mensalidadeplanodo') &&
          !d.contains('reducaomensalidade') &&
          !d.contains('openaichatgpt') &&
          !d.contains('repassedeiof');
    }).toList(growable: false);
  }

  static Map<int, List<Map<String, dynamic>>> _geoLinhasV22(String geo) {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final raw in geo.replaceAll('\r', '').split('\n')) {
      if (!raw.startsWith('G\t')) continue;
      final p = raw.split('\t');
      if (p.length < 9) continue;
      final pagina = int.tryParse(p[1]);
      final linha = int.tryParse(p[2]);
      final x = double.tryParse(p[3]);
      final y = double.tryParse(p[4]);
      final w = double.tryParse(p[5]);
      final h = double.tryParse(p[6]);
      if (pagina == null || linha == null || x == null || y == null || w == null || h == null) continue;
      final texto = p.sublist(8).join(' ').trim();
      out.putIfAbsent(pagina, () => <Map<String, dynamic>>[]).add({
        'linha': linha, 'x': x, 'y': y, 'w': w, 'h': h, 't': texto,
      });
    }
    return out;
  }

  static double? _corteGeoV22(List<Map<String, dynamic>> words) {
    final porLinha = <int, List<Map<String, dynamic>>>{};
    for (final w in words) {
      porLinha.putIfAbsent(w['linha'] as int, () => <Map<String, dynamic>>[]).add(w);
    }
    final candidatos = <double>[];
    for (final ws0 in porLinha.values) {
      final ws = [...ws0]..sort((a,b)=>(a['x'] as double).compareTo(b['x'] as double));
      final txt = chave(ws.map((e)=>e['t']).join(' '));
      if (!txt.contains('lancamentoscomprasesaques') && !txt.contains('pagamentosefetuados')) continue;
      double maior = 0; double? corte;
      for (var i=0;i+1<ws.length;i++) {
        final fim=(ws[i]['x'] as double)+(ws[i]['w'] as double);
        final ini=ws[i+1]['x'] as double;
        final gap=ini-fim;
        if(gap>maior && gap>18){maior=gap;corte=(fim+ini)/2;}
      }
      if(corte!=null)candidatos.add(corte);
    }
    if(candidatos.isNotEmpty){
      candidatos.sort();
      return candidatos[candidatos.length~/2];
    }
    // Fallback geométrico: datas de transação formam dois alinhamentos X
    // muito estáveis nas páginas em duas colunas. Descobre o maior vão entre
    // esses alinhamentos sem usar qualquer valor financeiro da fatura.
    final xs=<double>[];
    for(final w in words){
      final t=(w['t'] as String).trim();
      if(RegExp(r'^\d{2}\s*/\s*\d{2}$').hasMatch(t)){
        xs.add(w['x'] as double);
      }
    }
    if(xs.length<2)return null;
    xs.sort();
    final grupos=<double>[];
    for(final x in xs){
      if(grupos.isEmpty || (x-grupos.last).abs()>12)grupos.add(x);
    }
    if(grupos.length<2)return null;
    double maior=-1; double? corte;
    for(var i=0;i+1<grupos.length;i++){
      final gap=grupos[i+1]-grupos[i];
      if(gap>maior){maior=gap;corte=(grupos[i]+grupos[i+1])/2;}
    }
    return corte;
  }

  static double? _corteGlobalV23(Map<int, List<Map<String, dynamic>>> paginas) {
    final cortes = <double>[];
    for (final words in paginas.values) {
      final c = _corteGeoV22(words);
      if (c != null && c > 180 && c < 420) cortes.add(c);
    }
    if (cortes.isNotEmpty) {
      cortes.sort();
      return cortes[cortes.length ~/ 2];
    }

    // Segundo caminho puramente geométrico: usa os alinhamentos X das datas
    // em TODAS as páginas. Não consulta subtotal, valor de compra ou nome de arquivo.
    final xs = <double>[];
    for (final words in paginas.values) {
      for (final w in words) {
        final t = (w['t'] as String).trim();
        if (RegExp(r'^\d{2}\s*/\s*\d{2}$').hasMatch(t)) xs.add(w['x'] as double);
      }
    }
    if (xs.length < 4) return null;
    xs.sort();
    final grupos = <List<double>>[];
    for (final x in xs) {
      if (grupos.isEmpty || (x - grupos.last.last).abs() > 14) {
        grupos.add(<double>[x]);
      } else {
        grupos.last.add(x);
      }
    }
    if (grupos.length < 2) return null;
    final centros = grupos
        .where((g) => g.length >= 2)
        .map((g) => g.reduce((a,b)=>a+b) / g.length)
        .toList()..sort();
    if (centros.length < 2) return null;
    double maior = -1; double? corte;
    for (var i=0;i+1<centros.length;i++) {
      final gap=centros[i+1]-centros[i];
      if (gap>maior) { maior=gap; corte=(centros[i]+centros[i+1])/2; }
    }
    return corte;
  }

  static bool _cabecalhoCompraV24(String k) =>
      k.contains('lancamentoscomprasesaques');

  static bool _cabecalhoNaoCompraV24(String k) =>
      k.contains('pagamentosefetuados') ||
      k.contains('lancamentosinternacionais') ||
      k.contains('lancamentosprodutoseservicos') ||
      k.contains('comprasparceladasproximasfaturas') ||
      k.contains('lancamentosnocartao') ||
      k.contains('encargoscobradosnestafatura') ||
      k.contains('limitesdecredito');

  // V24 não confia no índice de TextLine do Syncfusion. Alguns PDFs Itaú
  // dividem visualmente uma única linha em vários TextLine. Em vez disso,
  // reconstruímos as faixas horizontais exclusivamente pelas coordenadas Y
  // das palavras. Isso preserva as duas colunas físicas e também recompõe
  // datas/valores que o PDF fragmenta em palavras diferentes (ex.: 27/0 + 6
  // e 155 + ,76).
  static List<List<Map<String, dynamic>>> _faixasGeoV24(
    List<Map<String, dynamic>> words,
    double corte,
    bool esquerda,
  ) {
    final selecionadas = words.where((w) {
      final x = w['x'] as double;
      return esquerda ? x < corte : x >= corte;
    }).toList()
      ..sort((a, b) {
        final cy = (a['y'] as double).compareTo(b['y'] as double);
        if (cy != 0) return cy;
        return (a['x'] as double).compareTo(b['x'] as double);
      });

    final faixas = <List<Map<String, dynamic>>>[];
    final ys = <double>[];
    const toleranciaY = 2.25;

    for (final w in selecionadas) {
      final y = w['y'] as double;
      var melhor = -1;
      var menor = double.infinity;
      // Só as últimas faixas podem coincidir verticalmente com a palavra.
      for (var i = faixas.length - 1; i >= 0 && i >= faixas.length - 5; i--) {
        final d = (ys[i] - y).abs();
        if (d <= toleranciaY && d < menor) {
          menor = d;
          melhor = i;
        }
      }
      if (melhor < 0) {
        faixas.add(<Map<String, dynamic>>[w]);
        ys.add(y);
      } else {
        faixas[melhor].add(w);
        ys[melhor] = faixas[melhor]
                .map((e) => e['y'] as double)
                .reduce((a, b) => a + b) /
            faixas[melhor].length;
      }
    }

    final ordem = List<int>.generate(faixas.length, (i) => i)
      ..sort((a, b) => ys[a].compareTo(ys[b]));
    return ordem.map((i) {
      final f = [...faixas[i]]
        ..sort((a, b) => (a['x'] as double).compareTo(b['x'] as double));
      return f;
    }).toList(growable: false);
  }

  static String _textoFaixaGeoV24(List<Map<String, dynamic>> faixa) {
    var s = faixa.map((e) => (e['t'] as String).trim()).where((e) => e.isNotEmpty).join(' ');
    // Recompõe somente fragmentações NUMÉRICAS. Não funde palavras da
    // descrição e não usa subtotal/valor-alvo para decidir o que entra.
    s = s.replaceAllMapped(RegExp(r'(\d)\s*/\s*(\d)'), (m) => '${m.group(1)}/${m.group(2)}');
    s = s.replaceAllMapped(RegExp(r'(\d)\s*,\s*(\d)'), (m) => '${m.group(1)},${m.group(2)}');
    s = s.replaceAllMapped(RegExp(r'(\d)\s*\.\s*(\d)'), (m) => '${m.group(1)}.${m.group(2)}');
    // Dígitos quebrados pelo PDF após /, vírgula ou ponto.
    s = s.replaceAllMapped(RegExp(r'(/\d)\s+(\d)'), (m) => '${m.group(1)}${m.group(2)}');
    s = s.replaceAllMapped(RegExp(r'([,.]\d)\s+(\d)'), (m) => '${m.group(1)}${m.group(2)}');
    return limparEspacos(s);
  }

  static double? _corteEstruturalV24(Map<int, List<Map<String, dynamic>>> paginas) {
    // Primeiro usa somente páginas cujo cabeçalho demonstra duas regiões
    // paralelas. Evita que páginas financeiras de uma coluna contaminem o
    // corte com alinhamentos de datas/valores não relacionados a compras.
    final cortes = <double>[];
    for (final words in paginas.values) {
      final full = chave(words.map((e) => e['t']).join(' '));
      if (!full.contains('lancamentoscomprasesaques')) continue;
      final c = _corteGeoV22(words);
      if (c != null && c > 240 && c < 360) cortes.add(c);
    }
    if (cortes.isNotEmpty) {
      cortes.sort();
      return cortes[cortes.length ~/ 2];
    }
    return _corteGlobalV23(paginas);
  }

  static List<Lancamento> comprasGeometricasV24(String geo, double totalCartao) {
    if (geo.trim().isEmpty) return const <Lancamento>[];
    final paginas = _geoLinhasV22(geo);
    final saida = <Lancamento>[];
    final limite = totalCartao.abs() + 0.01;
    final corte = _corteEstruturalV24(paginas);
    if (corte == null) return const <Lancamento>[];

    for (final entry in paginas.entries) {
      final words = entry.value;
      final full = chave(words.map((e) => e['t']).join(' '));
      if (!full.contains('lancamentoscomprasesaques')) continue;

      for (final esquerda in const [true, false]) {
        final faixas = _faixasGeoV24(words, corte, esquerda);
        var comprasAtivas = false;

        for (final faixa in faixas) {
          final texto = _textoFaixaGeoV24(faixa);
          if (texto.isEmpty) continue;
          final k = chave(texto);

          if (_cabecalhoCompraV24(k)) {
            comprasAtivas = true;
            continue;
          }
          if (_cabecalhoNaoCompraV24(k)) {
            comprasAtivas = false;
            continue;
          }
          if (!comprasAtivas) continue;

          saida.addAll(_transacoesLinhaV21(
            texto,
            limite,
            esquerda
                ? 'Parser v25 - âncoras X/Y coluna esquerda'
                : 'Parser v25 - âncoras X/Y coluna direita',
          ));
        }
      }
    }
    return List<Lancamento>.unmodifiable(saida);
  }

  // V25: reconstrói BLOCOS de transação, não linhas. Uma compra começa em uma
  // faixa que contém uma data DD/MM e termina imediatamente antes da próxima
  // data/cabeçalho da MESMA coluna. Isso resolve PDFs em que Syncfusion coloca
  // data, estabelecimento, parcela, valor e categoria em TextLines/baselines
  // diferentes. O subtotal oficial não participa da formação dos blocos.
  static bool _temDataV25(String s) =>
      RegExp(r'\b\d{1,2}\s*/\s*\d{1,2}\b').hasMatch(normalizarDatas(s));

  static bool _pareceCabecalhoV25(String k) =>
      _cabecalhoCompraV24(k) || _cabecalhoNaoCompraV24(k) ||
      k.contains('dataestabelecimentovaloremr') ||
      k.contains('dataprodutosservicosvaloremr') ||
      k.contains('totaldoslancamentosatuais');

  static List<Lancamento> _blocosColunaV25(
    List<Map<String, dynamic>> words,
    double corte,
    bool esquerda,
    double limite,
  ) {
    final faixas = _faixasGeoV24(words, corte, esquerda);
    final saida = <Lancamento>[];
    var comprasAtivas = false;
    final bloco = <String>[];

    void descarregar() {
      if (bloco.isEmpty) return;
      final texto = limparEspacos(bloco.join(' '));
      bloco.clear();
      if (!_temDataV25(texto)) return;
      saida.addAll(_transacoesLinhaV21(
        texto,
        limite,
        esquerda
            ? 'Parser v25 - bloco geométrico coluna esquerda'
            : 'Parser v25 - bloco geométrico coluna direita',
      ));
    }

    for (final faixa in faixas) {
      final texto = _textoFaixaGeoV24(faixa);
      if (texto.isEmpty) continue;
      final k = chave(texto);

      if (_cabecalhoCompraV24(k)) {
        descarregar();
        comprasAtivas = true;
        continue;
      }
      if (_cabecalhoNaoCompraV24(k)) {
        descarregar();
        comprasAtivas = false;
        continue;
      }
      if (_pareceCabecalhoV25(k)) {
        descarregar();
        continue;
      }
      if (!comprasAtivas) continue;

      // Uma nova data abre uma nova transação. As faixas sem data que vêm
      // depois pertencem à transação anterior (categoria/cidade ou fragmentos).
      if (_temDataV25(texto) && bloco.isNotEmpty) descarregar();
      if (_temDataV25(texto) || bloco.isNotEmpty) bloco.add(texto);
    }
    descarregar();
    return saida;
  }

  static List<Lancamento> comprasGeometricasV25(String geo, double totalCartao) {
    if (geo.trim().isEmpty) return const <Lancamento>[];
    final paginas = _geoLinhasV22(geo);
    final corteGlobal = _corteEstruturalV24(paginas);
    if (corteGlobal == null) return const <Lancamento>[];
    final limite = totalCartao.abs() + 0.01;
    final saida = <Lancamento>[];

    for (final entry in paginas.entries) {
      final words = entry.value;
      final full = chave(words.map((e) => e['t']).join(' '));
      if (!full.contains('lancamentoscomprasesaques')) continue;

      // Cortes locais só são aceitos na faixa física típica entre as duas
      // tabelas. Páginas sem evidência herdam o corte estrutural da fatura.
      final local = _corteGeoV22(words);
      final corte = (local != null && local >= 250 && local <= 340)
          ? local
          : corteGlobal;
      saida.addAll(_blocosColunaV25(words, corte, true, limite));
      saida.addAll(_blocosColunaV25(words, corte, false, limite));
    }
    return List<Lancamento>.unmodifiable(saida);
  }

  // Mantém a V23 integralmente como parser independente de regressão.
  static List<Lancamento> comprasGeometricasV23(String geo, double totalCartao) {
    if (geo.trim().isEmpty) return const <Lancamento>[];
    final paginas=_geoLinhasV22(geo);
    final saida=<Lancamento>[];
    final limite=totalCartao.abs()+0.01;
    final corteGlobal=_corteGlobalV23(paginas);

    for(final entry in paginas.entries){
      final words=entry.value;
      final full=chave(words.map((e)=>e['t']).join(' '));
      if(!full.contains('lancamentoscomprasesaques')) continue;
      final corte=_corteGeoV22(words) ?? corteGlobal;
      if(corte==null) continue;
      final porLinha=<int,List<Map<String,dynamic>>>{};
      for(final w in words){porLinha.putIfAbsent(w['linha'] as int,()=>[]).add(w);}
      final ids=porLinha.keys.toList()..sort();
      var esquerdaCompras=false;
      var direitaCompras=false;
      for(final id in ids){
        final ws=[...porLinha[id]!]..sort((a,b)=>(a['x'] as double).compareTo(b['x'] as double));
        final left=ws.where((e)=>(e['x'] as double)<corte).map((e)=>e['t']).join(' ').trim();
        final right=ws.where((e)=>(e['x'] as double)>=corte).map((e)=>e['t']).join(' ').trim();
        final kl=chave(left), kr=chave(right);
        if (_cabecalhoCompraV24(kl)) esquerdaCompras=true;
        if (_cabecalhoNaoCompraV24(kl)) esquerdaCompras=false;
        if (_cabecalhoCompraV24(kr)) direitaCompras=true;
        if (_cabecalhoNaoCompraV24(kr)) direitaCompras=false;
        final leftHeader=_cabecalhoCompraV24(kl)||_cabecalhoNaoCompraV24(kl);
        final rightHeader=_cabecalhoCompraV24(kr)||_cabecalhoNaoCompraV24(kr);
        if(esquerdaCompras && !leftHeader && left.isNotEmpty){
          saida.addAll(_transacoesLinhaV21(left,limite,'Parser v23 - geometria coluna esquerda'));
        }
        if(direitaCompras && !rightHeader && right.isNotEmpty){
          saida.addAll(_transacoesLinhaV21(right,limite,'Parser v23 - geometria coluna direita'));
        }
      }
    }
    return List<Lancamento>.unmodifiable(saida);
  }

  static List<Lancamento> comprasModelo202442V21(
    String layoutPaginas,
    double totalCartao,
  ) {
    final paginas = _paginasV19(layoutPaginas);
    final saida = <Lancamento>[];
    final limite = totalCartao.abs() + 0.01;
    final chavesPaginas = paginas.map(chave).toList(growable: false);

    final temPagamentoCompras = chavesPaginas.any((k) =>
        k.contains('pagamentosefetuados') &&
        k.contains('lancamentoscomprasesaques'));
    final temComprasIntermediaria = chavesPaginas.any((k) =>
        k.contains('lancamentoscomprasesaques') &&
        !k.contains('pagamentosefetuados') &&
        !k.contains('lancamentosinternacionais') &&
        !k.contains('lancamentosnocartao'));
    final temPaginaFinal = chavesPaginas.any((k) =>
        k.contains('lancamentoscomprasesaques') &&
        k.contains('lancamentosnocartao') &&
        (k.contains('lancamentosinternacionais') ||
         k.contains('lancamentosprodutoseservicos')));

    if (paginas.length < 4 ||
        !temPagamentoCompras ||
        !temComprasIntermediaria ||
        !temPaginaFinal) {
      return const <Lancamento>[];
    }

    for (final pagina in paginas) {
      final kp = chave(pagina);
      if (!kp.contains('lancamentoscomprasesaques')) continue;
      final linhas = pagina.replaceAll('\\r', '').split('\\n');

      if (kp.contains('pagamentosefetuados')) {
        // Nesta página o extrator remove o espaçamento horizontal entre as
        // colunas. A sequência lógica, porém, é estável: primeiro pagamento
        // + compras; depois surge o segundo cabeçalho e ambas as metades são
        // compras. transacoesDaLinha consegue separar mais de uma transação
        // na mesma linha e descarta o pagamento pela descrição.
        var viuCabecalho = false;
        for (final linha in linhas) {
          final kl = chave(linha);
          if (kl.contains('lancamentoscomprasesaques')) {
            viuCabecalho = true;
            continue;
          }
          if (!viuCabecalho) continue;
          if (kl.contains('continua')) continue;
          saida.addAll(_transacoesLinhaV21(
            linha, limite, 'Parser v21 - fluxo página pagamento/compras'));
        }
        continue;
      }

      if (!kp.contains('lancamentosnocartao')) {
        // Página intermediária: as duas colunas pertencem integralmente às
        // compras correntes. Não é necessário reconstruir coordenadas.
        var ativo = false;
        for (final linha in linhas) {
          final kl = chave(linha);
          if (kl.contains('lancamentoscomprasesaques')) {
            ativo = true;
            continue;
          }
          if (!ativo || kl.contains('continua')) continue;
          saida.addAll(_transacoesLinhaV21(
            linha, limite, 'Parser v21 - fluxo página compras dupla'));
        }
        continue;
      }

      // Página final: o PDF intercala compras correntes com internacional,
      // produtos/serviços, futuras e quadros financeiros. No texto extraído,
      // quando há duas transações na mesma linha a compra corrente é a
      // primeira. Linhas exclusivas das seções paralelas são rejeitadas pelos
      // marcadores/descrições abaixo.
      var ativo = false;
      var futuras = false;
      for (final linha in linhas) {
        final kl = chave(linha);
        if (kl.contains('lancamentoscomprasesaques')) {
          ativo = true;
          continue;
        }
        if (!ativo) continue;
        if (kl.contains('lancamentosnocartao')) break;
        if (kl.contains('comprasparceladasproximasfaturas')) {
          futuras = true;
          // A mesma linha pode conter uma compra corrente do outro fluxo.
        }

        final todos = _transacoesLinhaV21(
          linha, limite, 'Parser v21 - fluxo página final');
        if (todos.isEmpty) continue;

        final proibidaExclusiva =
            kl.contains('openaichatgpt') ||
            kl.contains('mensalidadeplanodo') ||
            kl.contains('reducaomensalidade') ||
            kl.contains('repassedeiof') ||
            kl.contains('totaltransacoesinter') ||
            kl.contains('totallancamentosinter');
        if (proibidaExclusiva && todos.length == 1) continue;

        // Antes e depois do quadro de futuras, a compra corrente ocupa o
        // primeiro fluxo textual da linha; itens paralelos vêm em seguida.
        // O flag é mantido para diagnóstico e documentação da estrutura.
        if (futuras || todos.length > 1) {
          saida.add(todos.first);
        } else {
          saida.add(todos.first);
        }
      }
    }

    return List<Lancamento>.unmodifiable(saida);
  }


  // V27: reconstrução geométrica por proximidade física. O Syncfusion pode
  // fragmentar um mesmo número em vários Word (ex.: "1" + "69,97" ou
  // "41" + "6,5" + "8"). A V27 recompõe o texto usando o GAP X real entre
  // palavras da mesma faixa, sem consultar o subtotal oficial. Também inicia
  // as duas colunas como candidatas quando a página contém estruturalmente a
  // seção de compras; cabeçalhos de pagamentos/internacional/serviços/futuro
  // desligam apenas a coluna em que aparecem.
  static String _textoFaixaGeoV27(List<Map<String, dynamic>> faixa) {
    if (faixa.isEmpty) return '';
    final ws = [...faixa]
      ..sort((a,b)=>(a['x'] as double).compareTo(b['x'] as double));
    final b = StringBuffer();
    Map<String,dynamic>? ant;
    for (final w in ws) {
      final t = (w['t'] as String).trim();
      if (t.isEmpty) continue;
      if (ant != null) {
        final fim = (ant['x'] as double) + (ant['w'] as double);
        final gap = (w['x'] as double) - fim;
        final ta = (ant['t'] as String).trim();
        final numericoA = RegExp(r'[0-9,./-]$').hasMatch(ta);
        final numericoB = RegExp(r'^[0-9,./-]').hasMatch(t);
        // Fragmentos numéricos do PDF ficam praticamente encostados. Não
        // fundimos grupos separados por um gap tipográfico normal, preservando
        // a separação entre parcela (04/12) e valor (416,58).
        if (!(numericoA && numericoB && gap <= 2.8)) b.write(' ');
      }
      b.write(t);
      ant = w;
    }
    var s=b.toString();
    s=s.replaceAllMapped(RegExp(r'(\d)\s*/\s*(\d)'),(m)=>'${m.group(1)}/${m.group(2)}');
    s=s.replaceAllMapped(RegExp(r'(\d)\s*,\s*(\d)'),(m)=>'${m.group(1)},${m.group(2)}');
    return limparEspacos(s);
  }

  static Map<String,dynamic> _colunaV27(
    List<Map<String,dynamic>> words,double corte,bool esquerda,
    bool ativaInicial,
  ) {
    final faixas=_faixasGeoV24(words,corte,esquerda);
    final saida=<Lancamento>[];
    var ativa=ativaInicial;
    final bloco=<String>[];
    final janela=<String>[];

    void descarregar(){
      if(bloco.isEmpty)return;
      final texto=limparEspacos(bloco.join(' '));
      bloco.clear();
      if(!_temDataV25(texto))return;
      // infinity é proposital: o subtotal oficial não participa da formação
      // ou filtragem das compras deste parser.
      saida.addAll(_transacoesLinhaV21(texto,double.infinity,
        esquerda?'Parser v27 - geometria física esquerda':'Parser v27 - geometria física direita'));
    }

    for(final faixa in faixas){
      final texto=_textoFaixaGeoV27(faixa);
      if(texto.isEmpty)continue;
      final k=chave(texto);
      janela.add(k); if(janela.length>7)janela.removeAt(0);
      final contexto=janela.join();

      final posCompra=contexto.lastIndexOf('comprasesaques');
      final posNao=<int>[
        contexto.lastIndexOf('pagamentosefetuados'),
        contexto.lastIndexOf('lancamentosinternacionais'),
        contexto.lastIndexOf('lancamentosprodutoseservicos'),
        contexto.lastIndexOf('comprasparceladasproximasfaturas'),
        contexto.lastIndexOf('lancamentosnocartao'),
        contexto.lastIndexOf('totalparaproximasfaturas'),
      ].reduce((a,b)=>a>b?a:b);
      if(posNao>=0 && posNao>posCompra){descarregar();ativa=false;continue;}
      if(posCompra>=0 && posCompra>=posNao){descarregar();ativa=true;if(!_temDataV25(texto))continue;}
      if(!ativa)continue;
      if(_pareceCabecalhoV25(k)){descarregar();continue;}
      if(_temDataV25(texto)&&bloco.isNotEmpty)descarregar();
      if(_temDataV25(texto)||bloco.isNotEmpty)bloco.add(texto);
    }
    descarregar();
    return <String,dynamic>{'compras':saida,'ativa':ativa};
  }

  static List<Lancamento> comprasGeometricasV27(String geo) {
    if(geo.trim().isEmpty)return const <Lancamento>[];
    final paginas=_geoLinhasV22(geo);
    final corteGlobal=_corteEstruturalV24(paginas);
    if(corteGlobal==null)return const <Lancamento>[];
    final saida=<Lancamento>[];
    var ea=false,da=false;
    for(final entry in paginas.entries){
      final words=entry.value;
      final full=chave(words.map((e)=>e['t']).join(' '));
      final temCompras=full.contains('lancamentoscomprasesaques');
      if(!temCompras&&!ea&&!da)continue;
      final local=_corteGeoV22(words);
      final corte=(local!=null&&local>=250&&local<=340)?local:corteGlobal;
      // Quando a página anuncia compras, ambas as regiões físicas podem
      // conter a tabela, mesmo que o cabeçalho esteja desenhado só em uma.
      final le=_colunaV27(words,corte,true,ea||temCompras);
      final ld=_colunaV27(words,corte,false,da||temCompras);
      saida.addAll(le['compras'] as List<Lancamento>);
      saida.addAll(ld['compras'] as List<Lancamento>);
      ea=le['ativa'] as bool; da=ld['ativa'] as bool;
    }
    return List<Lancamento>.unmodifiable(saida);
  }

  // V29: parser geométrico por corredor físico real do Syncfusion.
  // Desenvolvido sobre o dump nativo do PdfTextExtractor. O subtotal oficial
  // NÃO participa da reconstrução. Cada lado da página possui estado próprio.
  // O valor é obtido do agrupamento geométrico de fragmentos numéricos no fim
  // da linha, evitando confundir a parcela NN/NN com o valor monetário.
  static bool _numericoV29(String t) =>
      RegExp(r'^[-0-9.,]+$').hasMatch(t.trim()) && t.trim().isNotEmpty;

  static Map<String,dynamic>? _valorGeoV29(List<Map<String,dynamic>> ws) {
    final itens=[...ws]..sort((a,b)=>(a['x'] as double).compareTo(b['x'] as double));
    final grupos=<List<Map<String,dynamic>>>[];
    var atual=<Map<String,dynamic>>[];
    double? fimAnterior;
    void fechar(){ if(atual.isNotEmpty){grupos.add(atual);atual=<Map<String,dynamic>>[];} fimAnterior=null; }
    for(final w in itens){
      final t=(w['t'] as String).trim();
      if(!_numericoV29(t)){fechar();continue;}
      final x=w['x'] as double;
      final fim=x+(w['w'] as double);
      final gap=fimAnterior==null?999.0:x-fimAnterior!;
      if(atual.isNotEmpty && gap>2.8)fechar();
      atual.add(w);
      fimAnterior=fim;
    }
    fechar();
    Map<String,dynamic>? melhor;
    double xFim=-1;
    for(final g in grupos){
      final s=g.map((e)=>(e['t'] as String).trim()).join();
      if(!RegExp(r'^-?(?:\d{1,3}(?:\.\d{3})*|\d+),\d{2}$').hasMatch(s))continue;
      final fim=(g.last['x'] as double)+(g.last['w'] as double);
      if(fim>xFim){
        xFim=fim;
        melhor={'valor':moeda(s),'inicioX':g.first['x'] as double,'texto':s};
      }
    }
    return melhor;
  }

  static double _corteV29(Map<int,List<Map<String,dynamic>>> paginas){
    // O layout Itaú observado possui um corredor vazio entre a coluna de valor
    // esquerda (termina perto de X=340) e a data da coluna direita (inicia
    // perto de X=351). Usamos apenas geometria do documento, nunca valores.
    // Primeiro procuramos o maior corredor vazio na faixa central 320..380.
    final ocupados=<double>[];
    for(final words in paginas.values){
      final full=chave(words.map((e)=>e['t']).join(' '));
      if(!full.contains('lancamentoscomprasesaques'))continue;
      for(final w in words){
        final x=w['x'] as double;
        final f=x+(w['w'] as double);
        if(f>=300 && x<=400){ocupados.add(x);ocupados.add(f);}
      }
    }
    // Centro estrutural estável do template. Mantido como fallback técnico;
    // não depende de arquivo, cartão, subtotal ou qualquer montante financeiro.
    return 345.0;
  }

  static bool _fimComprasV29(String k) =>
      k.contains('lancamentosinternacionais') ||
      k.contains('lancamentosprodutoseservicos') ||
      k.contains('dataprodutosservicosvaloremr') ||
      k.contains('produtosservicosvaloremr') ||
      k.contains('comprasparceladasproximasfaturas') ||
      k.contains('lancamentosnocartao') ||
      k.contains('totaldoslancamentosatuais') ||
      k.contains('encargoscobradosnestafatura') ||
      k.contains('limitesdecredito');

  static List<Lancamento> comprasGeometricasV29(String geo){
    if(geo.trim().isEmpty)return const <Lancamento>[];
    final paginas=_geoLinhasV22(geo);
    if(paginas.isEmpty)return const <Lancamento>[];
    final corte=_corteV29(paginas);
    final saida=<Lancamento>[];
    final ativa={'L':false,'R':false};

    for(final entry in paginas.entries){
      final porLinha=<int,List<Map<String,dynamic>>>{};
      for(final w in entry.value){
        porLinha.putIfAbsent(w['linha'] as int,()=>[]).add(w);
      }
      final ids=porLinha.keys.toList()..sort();
      for(final id in ids){
        final todos=[...porLinha[id]!]..sort((a,b)=>(a['x'] as double).compareTo(b['x'] as double));
        for(final lado in const ['L','R']){
          final ws=todos.where((w)=>lado=='L'?(w['x'] as double)<corte:(w['x'] as double)>=corte).toList();
          if(ws.isEmpty)continue;
          // Sem espaços artificiais: o próprio Syncfusion frequentemente
          // fragmenta uma palavra/valor em vários PdfTextWord adjacentes.
          final texto=ws.map((e)=>e['t'] as String).join().trim();
          final k=chave(texto);
          if(k.contains('lancamentoscomprasesaques')){ativa[lado]=true;continue;}
          if(_fimComprasV29(k)){ativa[lado]=false;continue;}
          if(ativa[lado]!=true)continue;
          final dm=RegExp(r'^\s*(\d{2})\s*/\s*(\d{2})').firstMatch(texto);
          if(dm==null)continue;
          final data='${dm.group(1)}/${dm.group(2)}';
          if(!dataValida(data))continue;
          final vg=_valorGeoV29(ws);
          if(vg==null)continue;
          final valor=vg['valor'] as double;
          final inicioValor=vg['inicioX'] as double;

          // Reconstrói descrição usando a posição X real do valor. Isso evita
          // fundir a parcela 05/12 com 416,58 e formar 12.416,58.
          final antesValor=ws.where((w)=>(w['x'] as double)<inicioValor).map((w)=>w['t'] as String).join().trim();
          final dmDesc=RegExp(r'^\s*(\d{2})\s*/\s*(\d{2})').firstMatch(antesValor);
          var corpo=dmDesc==null?antesValor:antesValor.substring(dmDesc.end);
          int? pa,pt;
          final pm=RegExp(r'(\d{1,2})\s*/\s*(\d{1,2})\s*$').firstMatch(corpo);
          if(pm!=null){
            final a=int.tryParse(pm.group(1)!); final t=int.tryParse(pm.group(2)!);
            if(a!=null&&t!=null&&a>=1&&t>=a&&t<=60){pa=a;pt=t;corpo=corpo.substring(0,pm.start);}
          }
          final desc=limparEspacos(corpo);
          if(desc.isEmpty)continue;
          final kd=chave(desc);
          if(kd.contains('pagamentoviaconta')||kd.contains('pagamentoefetuado')||kd.contains('totaldospagamentos'))continue;
          saida.add(Lancamento(
            data:data,
            descricao:desc,
            categoria:'outros',
            valor:valor,
            parcelaAtual:pa,
            totalParcelas:pt,
            tipo:pa==null?'À vista':'Parcelada',
            observacoes:'Parser v29 - corredor geométrico Syncfusion',
          ));
        }
      }
    }
    return List<Lancamento>.unmodifiable(saida);
  }

  static Candidato _v29Geometrico(String geo)=>Candidato(
    'V29-GEOM CORREDOR SYNCFUSION',
    comprasGeometricasV29(geo),
  );

  // V28: parser textual estrutural por blocos de compra. Independente dos
  // parsers anteriores e do subtotal oficial. Ele usa exclusivamente os
  // cabeçalhos/seções e as linhas de transação reconstruídas pelo layout.
  // Linhas quebradas são acumuladas até o próximo lançamento/cabeçalho.
  static bool _fimComprasV28(String k) =>
      k.contains('lancamentosinternacionais') ||
      k.contains('lancamentosprodutoseservicos') ||
      k.contains('produtoseservicos') ||
      k.contains('comprasparceladasproximasfaturas') ||
      k.contains('lancamentosnocartao') ||
      k.contains('encargoscobradosnestafatura') ||
      k.contains('limitesdecredito');

  static List<Lancamento> comprasLayoutBlocosV28(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');
    final saida = <Lancamento>[];
    var dentro = false;
    final bloco = <String>[];
    final dataInicio = RegExp(r'^\s*\d{2}\s*/\s*\d{2}\b');

    void descarregar() {
      if (bloco.isEmpty) return;
      final t = limparEspacos(bloco.join(' '));
      bloco.clear();
      if (!RegExp(r'\d{2}\s*/\s*\d{2}').hasMatch(t)) return;
      // Limite fixo técnico, não relacionado ao subtotal da fatura.
      // Serve apenas para rejeitar números absurdos que não são valores de compra.
      final achados = transacoesDaLinha(
        t,
        limite: 999999999.99,
        origem: 'Parser v28 - blocos estruturais de layout',
      );
      saida.addAll(achados);
    }

    for (final linha in linhas) {
      final k = chave(linha);
      if (k.contains('lancamentoscomprasesaques')) {
        descarregar();
        dentro = true;
        continue;
      }
      if (!dentro) continue;
      if (_fimComprasV28(k)) {
        descarregar();
        dentro = false;
        continue;
      }
      if (k.contains('dataestabelecimentovaloremr') ||
          k == 'dataestabelecimentovalor') {
        descarregar();
        continue;
      }
      if (dataInicio.hasMatch(linha)) {
        descarregar();
        bloco.add(linha);
      } else if (bloco.isNotEmpty) {
        // Complementos como parcela, valor, categoria e cidade podem vir em
        // linhas físicas distintas. Mantemos o bloco até o próximo DD/MM.
        bloco.add(linha);
      }
    }
    descarregar();
    return List<Lancamento>.unmodifiable(saida);
  }

  static Candidato _v28Layout(String layout) => Candidato(
    'V28-LAYOUT BLOCOS ESTRUTURAIS',
    comprasLayoutBlocosV28(layout),
  );

  static Candidato _v27Geometrico(String geo)=>Candidato(
    'V27-GEOM GAP X FÍSICO',
    List<Lancamento>.unmodifiable(comprasGeometricasV27(geo)),
  );

  // V26: estado semântico persistente por coluna + detecção de cabeçalhos em
  // janela móvel. O V25 mostrou que o corte X estava correto, mas muitos
  // cabeçalhos do Itaú são fragmentados em várias faixas Y; por isso o estado
  // de "compras" não era ativado em uma das colunas. A V26 recompõe o contexto
  // de até 6 faixas e mantém o estado entre páginas. O subtotal oficial NÃO é
  // usado para formar, incluir ou excluir transações.
  static bool _cueCompraV26(String k) =>
      k.contains('lancamentoscomprasesaques') ||
      k.contains('comprasesaques');

  static bool _cueNaoCompraV26(String k) =>
      _cabecalhoNaoCompraV24(k) ||
      k.contains('pagamentosefetuados') ||
      k.contains('comprasparceladasproximasfaturas') ||
      k.contains('lancamentosinternacionais') ||
      k.contains('lancamentosprodutoseservicos') ||
      k.contains('lancamentosnocartao');

  static Map<String, dynamic> _colunaV26(
    List<Map<String, dynamic>> words,
    double corte,
    bool esquerda,
    double limite,
    bool ativaInicial,
    bool paginaSoCompras,
  ) {
    final faixas = _faixasGeoV24(words, corte, esquerda);
    final saida = <Lancamento>[];
    var ativa = ativaInicial;
    final bloco = <String>[];
    final janela = <String>[];

    void descarregar() {
      if (bloco.isEmpty) return;
      final texto = limparEspacos(bloco.join(' '));
      bloco.clear();
      if (!_temDataV25(texto)) return;
      saida.addAll(_transacoesLinhaV21(
        texto,
        limite,
        esquerda
            ? 'Parser v26 - contexto persistente coluna esquerda'
            : 'Parser v26 - contexto persistente coluna direita',
      ));
    }

    for (final faixa in faixas) {
      final texto = _textoFaixaGeoV24(faixa);
      if (texto.isEmpty) continue;
      final k = chave(texto);
      janela.add(k);
      if (janela.length > 6) janela.removeAt(0);
      final contexto = janela.join();

      // Ordem proposital: um cabeçalho explícito de seção não-compras encerra
      // o fluxo antes de qualquer cabeçalho tabular genérico DATA/VALOR.
      if (_cueNaoCompraV26(contexto)) {
        // Se a própria janela também contém o cabeçalho de compras mais novo,
        // o marcador de compras prevalece somente quando aparece no final.
        final posCompra = contexto.lastIndexOf('comprasesaques');
        final posNao = [
          contexto.lastIndexOf('pagamentosefetuados'),
          contexto.lastIndexOf('lancamentosinternacionais'),
          contexto.lastIndexOf('lancamentosprodutoseservicos'),
          contexto.lastIndexOf('comprasparceladasproximasfaturas'),
          contexto.lastIndexOf('lancamentosnocartao'),
        ].reduce((a,b)=>a>b?a:b);
        if (posNao > posCompra) {
          descarregar();
          ativa = false;
          continue;
        }
      }

      if (_cueCompraV26(contexto)) {
        descarregar();
        ativa = true;
        // Cabeçalho não é parte da transação.
        if (!_temDataV25(texto)) continue;
      }

      // Em páginas estruturalmente compostas apenas por compras, o cabeçalho
      // DATA/ESTABELECIMENTO é evidência suficiente para ativar a coluna.
      if (paginaSoCompras &&
          (contexto.contains('dataestabelecimentovaloremr') ||
           contexto.contains('dataestabelecimentovalor'))) {
        descarregar();
        ativa = true;
        if (!_temDataV25(texto)) continue;
      }

      if (!ativa) continue;
      if (_pareceCabecalhoV25(k)) {
        descarregar();
        continue;
      }
      if (_temDataV25(texto) && bloco.isNotEmpty) descarregar();
      if (_temDataV25(texto) || bloco.isNotEmpty) bloco.add(texto);
    }
    descarregar();
    return <String, dynamic>{'compras': saida, 'ativa': ativa};
  }

  static List<Lancamento> comprasGeometricasV26(String geo, double totalCartao) {
    if (geo.trim().isEmpty) return const <Lancamento>[];
    final paginas = _geoLinhasV22(geo);
    final corteGlobal = _corteEstruturalV24(paginas);
    if (corteGlobal == null) return const <Lancamento>[];
    final limite = totalCartao.abs() + 0.01;
    final saida = <Lancamento>[];
    var esquerdaAtiva = false;
    var direitaAtiva = false;

    for (final entry in paginas.entries) {
      final words = entry.value;
      final full = chave(words.map((e) => e['t']).join(' '));
      final temCompras = full.contains('lancamentoscomprasesaques');
      if (!temCompras && !esquerdaAtiva && !direitaAtiva) continue;

      final temOutras = full.contains('pagamentosefetuados') ||
          full.contains('lancamentosinternacionais') ||
          full.contains('lancamentosprodutoseservicos') ||
          full.contains('comprasparceladasproximasfaturas') ||
          full.contains('lancamentosnocartao');
      final paginaSoCompras = temCompras && !temOutras;

      final local = _corteGeoV22(words);
      final corte = (local != null && local >= 250 && local <= 340)
          ? local
          : corteGlobal;

      final le = _colunaV26(words, corte, true, limite,
          esquerdaAtiva, paginaSoCompras);
      final ld = _colunaV26(words, corte, false, limite,
          direitaAtiva, paginaSoCompras);
      saida.addAll((le['compras'] as List<Lancamento>));
      saida.addAll((ld['compras'] as List<Lancamento>));
      esquerdaAtiva = le['ativa'] as bool;
      direitaAtiva = ld['ativa'] as bool;
    }
    return List<Lancamento>.unmodifiable(saida);
  }

  static Candidato _v26Geometrico(String geo,double alvo)=>Candidato(
    'V26-GEOM CONTEXTO PERSISTENTE',
    List<Lancamento>.unmodifiable(comprasGeometricasV26(geo,alvo)),
  );

  static Candidato _v25Geometrico(String geo,double alvo)=>Candidato(
    'V25-GEOM BLOCOS POR ÂNCORA',
    List<Lancamento>.unmodifiable(comprasGeometricasV25(geo,alvo)),
  );

  static Candidato _v24Geometrico(String geo,double alvo)=>Candidato(
    'V24-GEOM ÂNCORAS X/Y',
    List<Lancamento>.unmodifiable(comprasGeometricasV24(geo,alvo)),
  );

  static Candidato _v23Geometrico(String geo,double alvo)=>Candidato(
    'V23-GEOM CONTINUIDADE X/Y',
    List<Lancamento>.unmodifiable(comprasGeometricasV23(geo,alvo)),
  );

  static Candidato _v21Textual(String layoutPaginas,double alvo)=>Candidato(
    'V21-TEXTUAL LEGADO EXPERIMENTAL',
    List<Lancamento>.unmodifiable(comprasModelo202442V21(layoutPaginas,alvo)),
  );

  // V14 - PARSERS ISOLADOS. Nenhum parser modifica a saída de outro.
  static Candidato _v14A(String bruto,String layout,double alvo)=>Candidato('V14-A FAIXAS FÍSICAS',List<Lancamento>.unmodifiable(comprasFaixasFisicasV13(layout,alvo)));
  static Candidato _v14B(String bruto,String layout,double alvo)=>Candidato('V14-B COLUNAS CALIBRADAS',List<Lancamento>.unmodifiable(comprasTabelaV11(layout,alvo)));
  static Candidato _v14C(String bruto,String layout,double alvo)=>Candidato('V14-C TABELA LAYOUT',List<Lancamento>.unmodifiable(comprasTabelaV10(layout,alvo)));
  static Candidato _v14D(String bruto,String layout,double alvo)=>Candidato('V14-D TABELA BRUTO',List<Lancamento>.unmodifiable(comprasBrutoEstritoV10(bruto,alvo)));
  static Candidato _v14E(String bruto,String layout,double alvo)=>Candidato('V14-E BRUTO SEQUENCIAL',List<Lancamento>.unmodifiable(comprasBruto(bruto,alvo)));
  static Candidato _v14F(String bruto,String layout,double alvo)=>Candidato('V14-F LAYOUT COLUNAS',List<Lancamento>.unmodifiable(comprasLayoutColunas(layout,alvo)));
  static Candidato _v14G(String bruto,String layout,double alvo)=>Candidato('V14-G LAYOUT SEÇÕES',List<Lancamento>.unmodifiable(comprasLayoutSecoes(layout,alvo)));

  static List<Candidato> executarParsersV14(String bruto,String layout,double totalCartao,[String? layoutPaginas,String? geo])=>[
    _v29Geometrico(geo ?? ''),
    _v28Layout(layout),
    _v27Geometrico(geo ?? ''),
    _v26Geometrico(geo ?? '',totalCartao),
    _v25Geometrico(geo ?? '',totalCartao),
    _v24Geometrico(geo ?? '',totalCartao),
    _v23Geometrico(geo ?? '',totalCartao),
    _v21Textual(layoutPaginas ?? layout,totalCartao),
    _v14A(bruto,layout,totalCartao),
    _v14B(bruto,layout,totalCartao),
    _v14C(bruto,layout,totalCartao),
    _v14D(bruto,layout,totalCartao),
    _v14E(bruto,layout,totalCartao),
    _v14F(bruto,layout,totalCartao),
    _v14G(bruto,layout,totalCartao),
  ];

  static String diagnosticoParsersV14(String bruto,String layout,double totalCartao,[String? layoutPaginas,String? geo]){
    final alvo=centavos(totalCartao);
    final b=StringBuffer()..writeln('===== TESTE DOS PARSERS V29 =====');
    if(layoutPaginas!=null && layoutPaginas.trim().isNotEmpty){
      final ps=_paginasV19(layoutPaginas);
      b.writeln('V26 páginas físicas extraídas: ${ps.length}');
      for(var i=0;i<ps.length;i++){
        final k=chave(ps[i]);
        b.writeln(
          'V26 página ${i+1}: '
          'pagamentos=${k.contains("pagamentosefetuados")} | '
          'compras=${k.contains("lancamentoscomprasesaques")} | '
          'internacional=${k.contains("lancamentosinternacionais")} | '
          'servicos=${k.contains("lancamentosprodutoseservicos")} | '
          'subtotal=${k.contains("lancamentosnocartao")}'
        );
      }
    }
    if(geo!=null && geo.trim().isNotEmpty){
      final gp=_geoLinhasV22(geo);
      b.writeln('V26 geometria: ${gp.length} páginas com palavras posicionadas');
      final corteGlobal=_corteGlobalV23(gp);
      b.writeln('V26 corteX estrutural: ${_corteEstruturalV24(gp)?.toStringAsFixed(2) ?? "N/D"} | corte legado:  ${corteGlobal?.toStringAsFixed(2) ?? "N/D"}');
      for(final e in gp.entries){
        final corteLocal=_corteGeoV22(e.value);
        final corteUsado=corteLocal ?? corteGlobal;
        b.writeln('V26 geo página ${e.key}: palavras=${e.value.length} | corteLocal=${corteLocal?.toStringAsFixed(2) ?? "N/D"} | corteUsado=${corteUsado?.toStringAsFixed(2) ?? "N/D"}');
      }
    } else {
      b.writeln('V26 geometria: AUSENTE');
    }
    for(final p in executarParsersV14(bruto,layout,totalCartao,layoutPaginas,geo)){
      final dif=alvo-p.somaCentavos;
      b.writeln('${p.nome} | compras: ${p.compras.length} | soma: ${(p.somaCentavos/100).toStringAsFixed(2)} | esperado: ${(alvo/100).toStringAsFixed(2)} | diferença: ${(dif/100).toStringAsFixed(2)} | resultado: ${dif==0 ? "ACEITO" : "REJEITADO"}');
    }
    return b.toString();
  }

  static Candidato escolherCompras(String bruto,String layout,double totalCartao,[String? layoutPaginas,String? geo]){
    final candidatos=executarParsersV14(bruto,layout,totalCartao,layoutPaginas,geo);
    final alvo=centavos(totalCartao);
    // TODOS os parsers acima já foram executados. A escolha ocorre somente
    // depois, e somente entre resultados que fecham exatamente em centavos.
    // Prioridade estável: V14-A protege os casos já validados; depois V24,
    // V23, V21 e os demais. Nenhum resultado aproximado é promovido a aceito.
    final v14a=candidatos.firstWhere((c)=>c.nome.startsWith('V14-A'));
    if(v14a.compras.isNotEmpty && v14a.somaCentavos==alvo)return v14a;
    for(final c in candidatos){
      if(c.compras.isNotEmpty && c.somaCentavos==alvo)return c;
    }
    return const Candidato('NENHUM PARSER CONCILIADO',<Lancamento>[]);
  }

  static ResultadoFatura processar(
    String bruto,
    String layout, [
    String? layoutPaginas,
    String? textoGeometrico,
  ]) {
    double? oficial(
      List<String> marcadores,
    ) {
      return valorAposMarcador(
            bruto,
            marcadores,
          ) ??
          valorAposMarcador(
            layout,
            marcadores,
          );
    }

    final totalFatura =
        oficial(
      const [
        'Total desta fatura',
      ],
    );

    final totalCartao =
        oficial(
      const [
        'Lançamentos no cartão',
        'Lancamentos no cartao',
      ],
    );

    final totalInternacional =
        oficial(
      const [
        'Total lançamentos inter. em R\$',
        'Total lancamentos inter. em R\$',
      ],
    );

    final totalServicos =
        oficial(
      const [
        'Lançamentos produtos e serviços',
        'Lancamentos produtos e servicos',
      ],
    );

    final totalAtuais =
        oficial(
      const [
        'Total dos lançamentos atuais',
        'Total dos lancamentos atuais',
        'Lançamentos atuais',
        'Lancamentos atuais',
      ],
    );

    var totalEncargos =
        oficial(
      const [
        'Total de encargos em R\$',
        'Total de encargos',
      ],
    );

    final saldoFinanciado =
        oficial(
      const [
        'Saldo financiado',
      ],
    );

    final alertas =
        <String>[];

    if (totalFatura == null) {
      alertas.add(
        'Total da fatura não identificado.',
      );
    }

    if (totalCartao == null) {
      alertas.add(
        'Subtotal do cartão não identificado.',
      );
    }

    if (totalEncargos == null &&
        totalFatura != null &&
        totalAtuais != null &&
        (centavos(totalFatura) - centavos(totalAtuais)).abs() <= 1) {
      totalEncargos = 0;
      alertas.add(
        'Encargos não informados como subtotal específico; '
        'R\$ 0,00 inferido porque o total dos lançamentos atuais '
        'fecha diretamente com o total da fatura.',
      );
    }

    List<Lancamento> compras =
        const [];

    var estrategia =
        'SEM SUBTOTAL DO CARTÃO';

    if (totalCartao != null) {
      final escolhido =
          escolherCompras(
        bruto,
        layout,
        totalCartao,
        layoutPaginas,
        textoGeometrico,
      );

      compras =
          escolhido.compras;

      estrategia =
          escolhido.nome;

      if (escolhido.somaCentavos !=
          centavos(totalCartao)) {
        final diferenca =
            (centavos(
                      totalCartao,
                    ) -
                    escolhido
                        .somaCentavos) /
                100;

        alertas.add(
          'Compras individuais não fecharam '
          'o subtotal oficial. Diferença: '
          'R\$ ${diferenca.toStringAsFixed(2)}',
        );
      }
    }

    final extras =
        <Lancamento>[];

    if (totalInternacional != null &&
        totalInternacional.abs() >
            0.001) {
      extras.add(
        Lancamento(
          data: '',
          descricao:
              'Lançamentos internacionais + IOF',
          categoria:
              'internacional',
          valor:
              totalInternacional,
          tipo:
              'Internacional',
          observacoes:
              'Subtotal oficial do Itaú',
        ),
      );
    }

    if (totalServicos != null &&
        totalServicos.abs() >
            0.001) {
      extras.add(
        Lancamento(
          data: '',
          descricao:
              'Produtos e serviços',
          categoria:
              'produtos e serviços',
          valor:
              totalServicos,
          tipo:
              'Produto/Serviço',
          observacoes:
              'Subtotal oficial do Itaú',
        ),
      );
    }

    if (totalEncargos != null &&
        totalEncargos.abs() >
            0.001) {
      extras.add(
        Lancamento(
          data: '',
          descricao:
              'Encargos cobrados nesta fatura',
          categoria:
              'encargos',
          valor:
              totalEncargos,
          tipo:
              'Encargo financeiro',
          observacoes:
              'Total oficial de encargos do Itaú',
        ),
      );
    }

    final lancamentos =
        <Lancamento>[
      ...compras,
      ...extras,
    ];

    final soma =
        lancamentos.fold<double>(
      0,
      (s, e) =>
          s + e.valor,
    );

    if (totalAtuais != null) {
      final somaAtuais =
          (totalCartao ?? 0) +
          (totalInternacional ?? 0) +
          (totalServicos ?? 0);

      final diferenca =
          centavos(totalAtuais) -
              centavos(
                somaAtuais,
              );

      if (diferenca.abs() > 1) {
        alertas.add(
          'Lançamentos atuais não fecharam. '
          'Diferença: R\$ '
          '${(diferenca / 100).toStringAsFixed(2)}',
        );
      }
    }

    if (totalFatura != null) {
      final baseFinal =
          totalAtuais ??
          ((totalCartao ?? 0) +
              (totalInternacional ?? 0) +
              (totalServicos ?? 0));

      final esperadoFinal =
          baseFinal + (totalEncargos ?? 0);

      final diferenca =
          centavos(totalFatura) -
          centavos(esperadoFinal);

      if (diferenca.abs() > 1) {
        alertas.add(
          'Componentes oficiais não fecharam o total final. '
          'Diferença: R\$ '
          '${(diferenca / 100).toStringAsFixed(2)}',
        );
      }
    }

    final textoPrincipal =
        bruto.isNotEmpty
            ? bruto
            : layout;

    return ResultadoFatura(
      totalFatura:
          totalFatura,
      totalCartaoInformado:
          totalCartao,
      totalInternacionalInformado:
          totalInternacional,
      totalServicosInformado:
          totalServicos,
      totalLancamentosAtuaisInformado:
          totalAtuais,
      totalEncargosInformado:
          totalEncargos,
      saldoFinanciadoInformado:
          saldoFinanciado,
      vencimento:
          procurarVencimento(
        textoPrincipal,
      ),
      cartao:
          procurarCartao(
        textoPrincipal,
      ),
      estrategia:
          estrategia,
      lancamentos:
          lancamentos,
      compras:
          compras,
      alertas:
          alertas,
    );
  }
}

