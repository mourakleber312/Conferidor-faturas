import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() => runApp(const ConferidorApp());

class Lancamento {
  final String data;
  final String descricao;
  final String categoria;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;
  final String tipo;
  final String observacoes;

  const Lancamento({
    required this.data,
    required this.descricao,
    required this.categoria,
    required this.valor,
    required this.tipo,
    this.parcelaAtual,
    this.totalParcelas,
    this.observacoes = '',
  });

  bool get parcelada => parcelaAtual != null && totalParcelas != null;
}

class ResultadoFatura {
  final double? totalFatura;
  final double? totalCartaoInformado;
  final double? totalInternacionalInformado;
  final double? totalServicosInformado;
  final double? totalLancamentosAtuaisInformado;
  final double? totalEncargosInformado;
  final double? saldoFinanciadoInformado;
  final String vencimento;
  final String cartao;
  final String estrategia;
  final List<Lancamento> lancamentos;
  final List<Lancamento> compras;
  final List<String> alertas;

  const ResultadoFatura({
    required this.totalFatura,
    required this.lancamentos,
    required this.compras,
    this.totalCartaoInformado,
    this.totalInternacionalInformado,
    this.totalServicosInformado,
    this.totalLancamentosAtuaisInformado,
    this.totalEncargosInformado,
    this.saldoFinanciadoInformado,
    this.vencimento = '',
    this.cartao = '',
    this.estrategia = '',
    this.alertas = const [],
  });

  double get soma =>
      lancamentos.fold<double>(0, (s, e) => s + e.valor);

  double get somaCompras =>
      compras.fold<double>(0, (s, e) => s + e.valor);

  double? get diferenca =>
      totalFatura == null ? null : totalFatura! - soma;

  double? get diferencaCartao =>
      totalCartaoInformado == null
          ? null
          : totalCartaoInformado! - somaCompras;

  int get quantidadeParceladas =>
      compras.where((e) => e.parcelada).length;

  bool get comprasConciliadas =>
      totalCartaoInformado != null &&
      (ParserItau.centavos(totalCartaoInformado!) -
                  ParserItau.centavos(somaCompras))
              .abs() <=
          1;

  bool get lancamentosAtuaisConciliados {
    if (totalLancamentosAtuaisInformado == null ||
        totalCartaoInformado == null) {
      return false;
    }

    final componentes =
        ParserItau.centavos(totalCartaoInformado!) +
        ParserItau.centavos(totalInternacionalInformado ?? 0) +
        ParserItau.centavos(totalServicosInformado ?? 0);

    return (ParserItau.centavos(totalLancamentosAtuaisInformado!) -
                componentes)
            .abs() <=
        1;
  }

  bool get totalConciliado {
    if (totalFatura == null) {
      return false;
    }

    if (totalLancamentosAtuaisInformado != null) {
      final esperado =
          ParserItau.centavos(totalLancamentosAtuaisInformado!) +
          ParserItau.centavos(totalEncargosInformado ?? 0);

      return (ParserItau.centavos(totalFatura!) - esperado).abs() <= 1;
    }

    if (totalCartaoInformado == null) {
      return false;
    }

    final esperado =
        ParserItau.centavos(totalCartaoInformado!) +
        ParserItau.centavos(totalInternacionalInformado ?? 0) +
        ParserItau.centavos(totalServicosInformado ?? 0) +
        ParserItau.centavos(totalEncargosInformado ?? 0);

    return (ParserItau.centavos(totalFatura!) - esperado).abs() <= 1;
  }

  bool get conciliada =>
      comprasConciliadas &&
      totalConciliado &&
      (totalLancamentosAtuaisInformado == null ||
          lancamentosAtuaisConciliados);

  bool get falhaLeitura =>
      totalFatura == null &&
      totalCartaoInformado == null;

  String get status {
    if (falhaLeitura) {
      return 'FALHA DE LEITURA';
    }

    if (conciliada) {
      return 'CONCILIADA';
    }

    if (totalConciliado) {
      return 'INCOMPLETA';
    }

    return 'DIVERGENTE';
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;
  final String textoLayout;
  final String textoLayoutPaginas;
  final String textoBruto;

  const FaturaProcessada({
    required this.arquivo,
    required this.resultado,
    required this.textoLayout,
    required this.textoLayoutPaginas,
    required this.textoBruto,
  });
}

class ValorEncontrado {
  final int inicio;
  final int fim;
  final double valor;

  const ValorEncontrado(
    this.inicio,
    this.fim,
    this.valor,
  );
}

class Candidato {
  final String nome;
  final List<Lancamento> compras;

  const Candidato(
    this.nome,
    this.compras,
  );

  int get somaCentavos {
    return compras.fold<int>(
      0,
      (s, e) =>
          s + ParserItau.centavos(e.valor),
    );
  }
}

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

  static List<Lancamento> comprasModelo202442V20(
    String layoutPaginas,
    double totalCartao,
  ) {
    final paginas = _paginasV19(layoutPaginas);
    final saida = <Lancamento>[];
    final limite = totalCartao.abs() + 0.01;

    // Fingerprint exclusivamente estrutural. Não usa valores monetários,
    // nome do arquivo ou número do cartão para reconhecer o modelo.
    final chavesPaginas = paginas.map(chave).toList(growable: false);

    final temPaginaPagamentoCompras = chavesPaginas.any(
      (k) => k.contains('pagamentosefetuados') &&
             k.contains('lancamentoscomprasesaques'),
    );
    final temPaginaComprasIntermediaria = chavesPaginas.any(
      (k) => k.contains('lancamentoscomprasesaques') &&
             !k.contains('pagamentosefetuados') &&
             !k.contains('lancamentosinternacionais'),
    );
    final temPaginaFinalParalela = chavesPaginas.any(
      (k) => k.contains('lancamentoscomprasesaques') &&
             k.contains('lancamentosinternacionais') &&
             k.contains('lancamentosprodutoseservicos') &&
             k.contains('lancamentosnocartao'),
    );

    final reconhecido =
        paginas.length >= 4 &&
        temPaginaPagamentoCompras &&
        temPaginaComprasIntermediaria &&
        temPaginaFinalParalela;

    if (!reconhecido) return const <Lancamento>[];

    for (final pagina in paginas) {
      final kp = chave(pagina);
      if (!kp.contains('lancamentoscomprasesaques')) continue;

      final linhas = pagina.replaceAll('\r', '').split('\n');

      final temPagamento = kp.contains('pagamentosefetuados');
      final temInternacional = kp.contains('lancamentosinternacionais');

      if (temPagamento) {
        // Página 2 da 202442:
        //   início: pagamento (esquerda) | compras (direita)
        //   depois: compras (esquerda)  | compras (direita)
        var corte = -1;
        var esquerdaAtiva = false;
        var direitaAtiva = false;

        for (final linha in linhas) {
          final kl = chave(linha);

          if (kl.contains('pagamentosefetuados') &&
              kl.contains('lancamentoscomprasesaques')) {
            // O grande vão horizontal do cabeçalho separa as duas colunas.
            corte = _corteColunasV19(linha);
            direitaAtiva = true;
            continue;
          }

          // O segundo cabeçalho de compras, agora isolado na esquerda,
          // marca a transição da coluna esquerda de pagamento para compras.
          if (kl.contains('lancamentoscomprasesaques') &&
              !kl.contains('pagamentosefetuados')) {
            esquerdaAtiva = true;
          }

          if (corte <= 0) continue;
          final esq = linha.substring(0, corte.clamp(0, linha.length));
          final dir = linha.length > corte ? linha.substring(corte) : '';

          if (esquerdaAtiva) {
            saida.addAll(_segmentoComprasV19(
              esq,
              limite,
              'Parser v20 - 202442 página compras A coluna esquerda',
            ));
          }
          if (direitaAtiva) {
            saida.addAll(_segmentoComprasV19(
              dir,
              limite,
              'Parser v20 - 202442 página compras A coluna direita',
            ));
          }
        }
        continue;
      }

      if (!temInternacional) {
        // Página intermediária: duas tabelas de compras lado a lado.
        var corte = -1;
        for (final linha in linhas) {
          final kl = chave(linha);
          if (kl.contains('lancamentoscomprasesaques')) {
            corte = _corteColunasV19(linha);
            continue;
          }

          if (corte <= 0) continue;
          final esq = linha.substring(0, corte.clamp(0, linha.length));
          final dir = linha.length > corte ? linha.substring(corte) : '';
          saida.addAll(_segmentoComprasV19(
            esq,
            limite,
            'Parser v20 - 202442 página compras B coluna esquerda',
          ));
          saida.addAll(_segmentoComprasV19(
            dir,
            limite,
            'Parser v20 - 202442 página compras B coluna direita',
          ));
        }
        continue;
      }

      // Página final de lançamentos:
      // compras correntes exclusivamente à esquerda;
      // internacional, produtos/serviços, futuras e encargos à direita.
      var corte = -1;
      for (final linha in linhas) {
        final kl = chave(linha);
        if (kl.contains('lancamentoscomprasesaques') &&
            kl.contains('lancamentosinternacionais')) {
          corte = _corteColunasV19(linha);
          continue;
        }

        if (kl.contains('lancamentosnocartao')) break;
        if (corte <= 0) continue;

        final esq = linha.substring(0, corte.clamp(0, linha.length));
        saida.addAll(_segmentoComprasV19(
          esq,
          limite,
          'Parser v20 - 202442 página final coluna compras',
        ));
      }
    }

    return List<Lancamento>.unmodifiable(saida);
  }

  static Candidato _v15Modelo202442(
    String bruto,
    String layoutPaginas,
    double alvo,
  ) =>
      Candidato(
        'V20-202442 MODELO DEDICADO',
        List<Lancamento>.unmodifiable(
          comprasModelo202442V20(layoutPaginas, alvo),
        ),
      );

  // V14 - PARSERS ISOLADOS. Nenhum parser modifica a saída de outro.
  static Candidato _v14A(String bruto,String layout,double alvo)=>Candidato('V14-A FAIXAS FÍSICAS',List<Lancamento>.unmodifiable(comprasFaixasFisicasV13(layout,alvo)));
  static Candidato _v14B(String bruto,String layout,double alvo)=>Candidato('V14-B COLUNAS CALIBRADAS',List<Lancamento>.unmodifiable(comprasTabelaV11(layout,alvo)));
  static Candidato _v14C(String bruto,String layout,double alvo)=>Candidato('V14-C TABELA LAYOUT',List<Lancamento>.unmodifiable(comprasTabelaV10(layout,alvo)));
  static Candidato _v14D(String bruto,String layout,double alvo)=>Candidato('V14-D TABELA BRUTO',List<Lancamento>.unmodifiable(comprasBrutoEstritoV10(bruto,alvo)));
  static Candidato _v14E(String bruto,String layout,double alvo)=>Candidato('V14-E BRUTO SEQUENCIAL',List<Lancamento>.unmodifiable(comprasBruto(bruto,alvo)));
  static Candidato _v14F(String bruto,String layout,double alvo)=>Candidato('V14-F LAYOUT COLUNAS',List<Lancamento>.unmodifiable(comprasLayoutColunas(layout,alvo)));
  static Candidato _v14G(String bruto,String layout,double alvo)=>Candidato('V14-G LAYOUT SEÇÕES',List<Lancamento>.unmodifiable(comprasLayoutSecoes(layout,alvo)));

  static List<Candidato> executarParsersV14(String bruto,String layout,double totalCartao,[String? layoutPaginas])=>[
    _v15Modelo202442(bruto,layoutPaginas ?? layout,totalCartao),
    _v14A(bruto,layout,totalCartao),
    _v14B(bruto,layout,totalCartao),
    _v14C(bruto,layout,totalCartao),
    _v14D(bruto,layout,totalCartao),
    _v14E(bruto,layout,totalCartao),
    _v14F(bruto,layout,totalCartao),
    _v14G(bruto,layout,totalCartao),
  ];

  static String diagnosticoParsersV14(String bruto,String layout,double totalCartao,[String? layoutPaginas]){
    final alvo=centavos(totalCartao);
    final b=StringBuffer()..writeln('===== TESTE DOS PARSERS V20 =====');
    if(layoutPaginas!=null && layoutPaginas.trim().isNotEmpty){
      final ps=_paginasV19(layoutPaginas);
      b.writeln('V20 páginas físicas extraídas: ${ps.length}');
      for(var i=0;i<ps.length;i++){
        final k=chave(ps[i]);
        b.writeln(
          'V20 página ${i+1}: '
          'pagamentos=${k.contains("pagamentosefetuados")} | '
          'compras=${k.contains("lancamentoscomprasesaques")} | '
          'internacional=${k.contains("lancamentosinternacionais")} | '
          'servicos=${k.contains("lancamentosprodutoseservicos")} | '
          'subtotal=${k.contains("lancamentosnocartao")}'
        );
      }
    }
    for(final p in executarParsersV14(bruto,layout,totalCartao,layoutPaginas)){
      final dif=alvo-p.somaCentavos;
      b.writeln('${p.nome} | compras: ${p.compras.length} | soma: ${(p.somaCentavos/100).toStringAsFixed(2)} | esperado: ${(alvo/100).toStringAsFixed(2)} | diferença: ${(dif/100).toStringAsFixed(2)} | resultado: ${dif==0 ? "ACEITO" : "REJEITADO"}');
    }
    return b.toString();
  }

  static Candidato escolherCompras(String bruto,String layout,double totalCartao,[String? layoutPaginas]){
    final candidatos=executarParsersV14(bruto,layout,totalCartao,layoutPaginas);
    final alvo=centavos(totalCartao);
    for(final c in candidatos){
      if(c.compras.isNotEmpty && c.somaCentavos==alvo)return c;
    }
    // Nenhum fechamento natural. Se o parser dedicado reconheceu o modelo,
    // mantém sua saída como evidência. Caso contrário, usa o primeiro parser
    // legado não vazio. Não há "mais próximo", fusão ou subset-sum.
    if(candidatos.first.compras.isNotEmpty)return candidatos.first;
    for(final c in candidatos.skip(1)){
      if(c.compras.isNotEmpty)return c;
    }
    return candidatos.first;
  }

  static ResultadoFatura processar(
    String bruto,
    String layout, [
    String? layoutPaginas,
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

class ConferidorApp
    extends StatelessWidget {
  const ConferidorApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          false,
      title:
          'Conferidor de Faturas',
      theme:
          ThemeData(
        colorSchemeSeed:
            Colors.blue,
        useMaterial3:
            true,
      ),
      home:
          const HomePage(),
    );
  }
}

class HomePage
    extends StatefulWidget {
  const HomePage({
    super.key,
  });

  @override
  State<HomePage> createState() {
    return _HomePageState();
  }
}

class _HomePageState
    extends State<HomePage> {
  bool processando = false;
  bool gerandoExcel = false;
  bool gerandoDiagnostico = false;

  String status =
      'Selecione uma ou mais faturas Itaú em PDF.';

  final List<FaturaProcessada>
      faturas = [];

  int get conciliadas {
    return faturas
        .where(
          (f) =>
              f.resultado.conciliada,
        )
        .length;
  }

  int get incompletas {
    return faturas
        .where(
          (f) =>
              f.resultado.status ==
              'INCOMPLETA',
        )
        .length;
  }

  int get divergentes {
    return faturas
        .where(
          (f) =>
              f.resultado.status ==
              'DIVERGENTE',
        )
        .length;
  }

  int get falhas {
    return faturas
        .where(
          (f) =>
              f.resultado
                  .falhaLeitura,
        )
        .length;
  }

  int get compras {
    return faturas.fold<int>(
      0,
      (s, f) =>
          s +
          f.resultado
              .compras.length,
    );
  }

  int get parceladas {
    return faturas.fold<int>(
      0,
      (s, f) =>
          s +
          f.resultado
              .quantidadeParceladas,
    );
  }

  bool get todasConciliadas {
    return faturas.isNotEmpty &&
        faturas.every(
          (f) =>
              f.resultado.conciliada,
        );
  }

  double get totalFaturas {
    return faturas.fold<double>(
      0,
      (s, f) =>
          s +
          (f.resultado
                  .totalFatura ??
              0),
    );
  }

  double get totalLancamentos {
    return faturas.fold<double>(
      0,
      (s, f) =>
          s +
          f.resultado.soma,
    );
  }

  Future<void>
      selecionarFaturas() async {
    final escolha =
        await FilePicker.platform
            .pickFiles(
      type:
          FileType.custom,
      allowedExtensions:
          ['pdf'],
      allowMultiple:
          true,
    );

    if (escolha == null ||
        escolha.files.isEmpty) {
      return;
    }

    setState(() {
      processando = true;
      faturas.clear();
      status =
          'Iniciando processamento...';
    });

    for (var i = 0;
        i < escolha.files.length;
        i++) {
      final arquivo =
          escolha.files[i];

      if (mounted) {
        setState(() {
          status =
              'Analisando '
              '${i + 1} de '
              '${escolha.files.length}\n'
              '${arquivo.name}';
        });
      }

      try {
        if (arquivo.path == null) {
          throw Exception(
            'Arquivo sem caminho local.',
          );
        }

        final bytes =
            await File(
          arquivo.path!,
        ).readAsBytes();

        final pdf =
            PdfDocument(
          inputBytes:
              bytes,
        );

        final extrator =
            PdfTextExtractor(
          pdf,
        );

        final bruto =
            extrator.extractText();

        final layout =
            extrator.extractText(
          layoutText:
              true,
        );

        final paginasLayout = StringBuffer();
        for (var pagina = 0; pagina < pdf.pages.count; pagina++) {
          paginasLayout.writeln();
          paginasLayout.writeln('===== PAGINA ${pagina + 1} =====');
          paginasLayout.writeln(
            extrator.extractText(
              startPageIndex: pagina,
              endPageIndex: pagina,
              layoutText: true,
            ),
          );
        }
        final layoutPaginas = paginasLayout.toString();

        pdf.dispose();

        final resultado =
            ParserItau.processar(
          bruto,
          layout,
          layoutPaginas,
        );

        faturas.add(
          FaturaProcessada(
            arquivo:
                arquivo.name,
            resultado:
                resultado,
            textoLayout:
                layout,
            textoLayoutPaginas:
                layoutPaginas,
            textoBruto:
                bruto,
          ),
        );
      } catch (e, stack) {
        faturas.add(
          FaturaProcessada(
            arquivo:
                arquivo.name,
            textoLayout:
                '',
            textoLayoutPaginas:
                '',
            textoBruto:
                '',
            resultado:
                ResultadoFatura(
              totalFatura:
                  null,
              lancamentos:
                  const [],
              compras:
                  const [],
              alertas: [
                'Falha ao processar: $e',
                'Stack: $stack',
              ],
            ),
          ),
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      processando = false;

      status =
          '${faturas.length} '
          'fatura(s) processada(s).\n'
          '$conciliadas conciliada(s), '
          '$incompletas incompleta(s), '
          '$divergentes divergente(s), '
          '$falhas falha(s).';
    });
  }

  String diagnosticoFatura(
    FaturaProcessada f, {
    bool textos = true,
  }) {
    final r =
        f.resultado;

    final b =
        StringBuffer();

    b.writeln(
      '============================================================',
    );

    b.writeln(
      'DIAGNÓSTICO - CONFERIDOR DE FATURAS ITAÚ',
    );

    b.writeln(
      'Parser: v20 - parser 202442 por sequência estrutural de páginas + proteção de regressão',
    );

    b.writeln(
      'Arquivo: ${f.arquivo}',
    );

    b.writeln(
      'Status: ${r.status}',
    );

    b.writeln(
      'Estratégia: ${r.estrategia}',
    );

    b.writeln(
      'Vencimento: ${r.vencimento}',
    );

    b.writeln(
      'Cartão: ${r.cartao}',
    );

    b.writeln();
    b.write(
      ParserItau.diagnosticoParsersV14(
        f.textoBruto,
        f.textoLayout,
        r.totalCartaoInformado ?? 0,
        f.textoLayoutPaginas,
      ),
    );
    b.writeln();

    b.writeln();

    b.writeln(
      '===== CONFERÊNCIA =====',
    );

    b.writeln(
      'Total da fatura: ${r.totalFatura}',
    );

    b.writeln(
      'Subtotal cartão: ${r.totalCartaoInformado}',
    );

    b.writeln(
      'Soma compras: ${r.somaCompras}',
    );

    b.writeln(
      'Diferença cartão: ${r.diferencaCartao}',
    );

    b.writeln(
      'Total internacional: ${r.totalInternacionalInformado}',
    );

    b.writeln(
      'Produtos/serviços: ${r.totalServicosInformado}',
    );

    b.writeln(
      'Total lançamentos atuais: ${r.totalLancamentosAtuaisInformado}',
    );

    b.writeln(
      'Encargos: ${r.totalEncargosInformado}',
    );

    b.writeln(
      'Saldo financiado: ${r.saldoFinanciadoInformado}',
    );

    b.writeln(
      'Soma geral: ${r.soma}',
    );

    b.writeln(
      'Diferença geral (lista exportável): ${r.diferenca}',
    );

    b.writeln(
      'Compras x subtotal oficial: ${r.comprasConciliadas ? 'OK' : 'DIVERGENTE'}',
    );

    b.writeln(
      'Componentes oficiais x lançamentos atuais: '
      '${r.totalLancamentosAtuaisInformado == null ? 'N/D' : (r.lancamentosAtuaisConciliados ? 'OK' : 'DIVERGENTE')}',
    );

    b.writeln(
      'Componentes oficiais x total da fatura: ${r.totalConciliado ? 'OK' : 'DIVERGENTE'}',
    );

    b.writeln(
      'Compras: ${r.compras.length}',
    );

    b.writeln(
      'Parceladas: ${r.quantidadeParceladas}',
    );

    b.writeln();

    b.writeln(
      '===== ALERTAS =====',
    );

    if (r.alertas.isEmpty) {
      b.writeln(
        'Nenhum alerta.',
      );
    }

    for (final alerta
        in r.alertas) {
      b.writeln(
        '- $alerta',
      );
    }

    b.writeln();

    b.writeln(
      '===== COMPRAS RECONSTRUÍDAS =====',
    );

    for (final e
        in r.compras) {
      final parcela =
          e.parcelada
              ? '${e.parcelaAtual}/${e.totalParcelas}'
              : '';

      b.writeln(
        '${e.data} | '
        '${e.descricao} | '
        '${e.valor.toStringAsFixed(2)} | '
        '$parcela | '
        '${e.categoria} | '
        '${e.observacoes}',
      );
    }

    b.writeln();

    b.writeln(
      '===== TODOS OS LANÇAMENTOS =====',
    );

    for (final e
        in r.lancamentos) {
      b.writeln(
        '${e.data} | '
        '${e.descricao} | '
        '${e.valor.toStringAsFixed(2)} | '
        '${e.tipo} | '
        '${e.categoria} | '
        '${e.observacoes}',
      );
    }

    if (textos) {
      b.writeln();

      b.writeln(
        '===== TEXTO COM LAYOUT =====',
      );

      b.writeln(
        f.textoLayout,
      );

      b.writeln();

      b.writeln(
        '===== TEXTO BRUTO =====',
      );

      b.writeln(
        f.textoBruto,
      );
    }

    return b.toString();
  }

  Future<void> gerarDiagnostico(
    FaturaProcessada f,
  ) async {
    final pasta =
        await getTemporaryDirectory();

    final nome =
        f.arquivo.replaceAll(
      RegExp(
        r'[^A-Za-z0-9._-]',
      ),
      '_',
    );

    final arq =
        File(
      '${pasta.path}/'
      'diagnostico_$nome.txt',
    );

    await arq.writeAsString(
      diagnosticoFatura(f),
    );

    await Share.shareXFiles(
      [
        XFile(
          arq.path,
          mimeType:
              'text/plain',
        ),
      ],
    );
  }

  Future<void>
      gerarDiagnosticoTotal() async {
    if (faturas.isEmpty) {
      return;
    }

    setState(() {
      gerandoDiagnostico =
          true;
    });

    try {
      final b =
          StringBuffer();

      b.writeln(
        '============================================================',
      );

      b.writeln(
        'DIAGNÓSTICO TOTAL - CONFERIDOR DE FATURAS ITAÚ',
      );

      b.writeln(
        'Parser: v20',
      );

      b.writeln(
        '============================================================',
      );

      b.writeln(
        'Faturas processadas: ${faturas.length}',
      );

      b.writeln(
        'Conciliadas: $conciliadas',
      );

      b.writeln(
        'Incompletas: $incompletas',
      );

      b.writeln(
        'Divergentes: $divergentes',
      );

      b.writeln(
        'Falhas de leitura: $falhas',
      );

      b.writeln(
        'Compras reconstruídas: $compras',
      );

      b.writeln(
        'Compras parceladas: $parceladas',
      );

      b.writeln(
        'Valor total das faturas: '
        '${totalFaturas.toStringAsFixed(2)}',
      );

      b.writeln();

      b.writeln(
        '===== ÍNDICE =====',
      );

      for (var i = 0;
          i < faturas.length;
          i++) {
        final f =
            faturas[i];

        final r =
            f.resultado;

        b.writeln(
          '${i + 1}. '
          '${f.arquivo} | '
          '${r.status} | '
          'Total: ${r.totalFatura} | '
          'Cartão: ${r.totalCartaoInformado} | '
          'Compras: ${r.somaCompras.toStringAsFixed(2)} | '
          'Dif.: ${r.diferencaCartao} | '
          'Parceladas: ${r.quantidadeParceladas} | '
          '${r.estrategia}',
        );
      }

      for (var i = 0;
          i < faturas.length;
          i++) {
        b.writeln();

        b.writeln(
          '############################################################',
        );

        b.writeln(
          '# FATURA ${i + 1} DE ${faturas.length}',
        );

        b.writeln(
          '############################################################',
        );

        b.writeln(
          diagnosticoFatura(
            faturas[i],
          ),
        );
      }

      final pasta =
          await getTemporaryDirectory();

      final agora =
          DateTime.now();

      final nome =
          'diagnostico_total_'
          '${agora.year}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_'
          '${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}'
          '${agora.second.toString().padLeft(2, '0')}'
          '.txt';

      final arq =
          File(
        '${pasta.path}/$nome',
      );

      await arq.writeAsString(
        b.toString(),
      );

      await Share.shareXFiles(
        [
          XFile(
            arq.path,
            mimeType:
                'text/plain',
          ),
        ],
      );
    } finally {
      if (mounted) {
        setState(() {
          gerandoDiagnostico =
              false;
        });
      }
    }
  }

  Future<void> gerarExcel() async {
    if (!todasConciliadas) {
      return;
    }

    setState(() {
      gerandoExcel =
          true;
    });

    try {
      final excel =
          Excel.createExcel();

      final sheet =
          excel['Lançamentos'];

      sheet.appendRow(
        [
          TextCellValue(
            'Arquivo',
          ),
          TextCellValue(
            'Vencimento',
          ),
          TextCellValue(
            'Data',
          ),
          TextCellValue(
            'Descrição',
          ),
          TextCellValue(
            'Categoria',
          ),
          TextCellValue(
            'Valor',
          ),
          TextCellValue(
            'Parcela atual',
          ),
          TextCellValue(
            'Total parcelas',
          ),
          TextCellValue(
            'Tipo',
          ),
          TextCellValue(
            'Observações',
          ),
        ],
      );

      for (final f
          in faturas) {
        for (final e
            in f.resultado
                .lancamentos) {
          sheet.appendRow(
            [
              TextCellValue(
                f.arquivo,
              ),
              TextCellValue(
                f.resultado
                    .vencimento,
              ),
              TextCellValue(
                e.data,
              ),
              TextCellValue(
                e.descricao,
              ),
              TextCellValue(
                e.categoria,
              ),
              DoubleCellValue(
                e.valor,
              ),
              e.parcelaAtual ==
                      null
                  ? TextCellValue(
                      '',
                    )
                  : IntCellValue(
                      e.parcelaAtual!,
                    ),
              e.totalParcelas ==
                      null
                  ? TextCellValue(
                      '',
                    )
                  : IntCellValue(
                      e.totalParcelas!,
                    ),
              TextCellValue(
                e.tipo,
              ),
              TextCellValue(
                e.observacoes,
              ),
            ],
          );
        }
      }

      final conf =
          excel['Conferência'];

      conf.appendRow(
        [
          TextCellValue(
            'Arquivo',
          ),
          TextCellValue(
            'Total fatura',
          ),
          TextCellValue(
            'Subtotal cartão',
          ),
          TextCellValue(
            'Soma compras',
          ),
          TextCellValue(
            'Diferença cartão',
          ),
          TextCellValue(
            'Internacional',
          ),
          TextCellValue(
            'Produtos/serviços',
          ),
          TextCellValue(
            'Lançamentos atuais',
          ),
          TextCellValue(
            'Encargos',
          ),
          TextCellValue(
            'Soma geral',
          ),
          TextCellValue(
            'Diferença geral',
          ),
          TextCellValue(
            'Compras',
          ),
          TextCellValue(
            'Parceladas',
          ),
          TextCellValue(
            'Estratégia',
          ),
          TextCellValue(
            'Status',
          ),
        ],
      );

      for (final f
          in faturas) {
        final r =
            f.resultado;

        conf.appendRow(
          [
            TextCellValue(
              f.arquivo,
            ),
            DoubleCellValue(
              r.totalFatura ??
                  0,
            ),
            DoubleCellValue(
              r.totalCartaoInformado ??
                  0,
            ),
            DoubleCellValue(
              r.somaCompras,
            ),
            DoubleCellValue(
              r.diferencaCartao ??
                  0,
            ),
            DoubleCellValue(
              r.totalInternacionalInformado ??
                  0,
            ),
            DoubleCellValue(
              r.totalServicosInformado ??
                  0,
            ),
            DoubleCellValue(
              r.totalLancamentosAtuaisInformado ??
                  0,
            ),
            DoubleCellValue(
              r.totalEncargosInformado ??
                  0,
            ),
            DoubleCellValue(
              r.soma,
            ),
            DoubleCellValue(
              r.diferenca ??
                  0,
            ),
            IntCellValue(
              r.compras.length,
            ),
            IntCellValue(
              r.quantidadeParceladas,
            ),
            TextCellValue(
              r.estrategia,
            ),
            TextCellValue(
              r.status,
            ),
          ],
        );
      }

      if (excel.tables
          .containsKey(
        'Sheet1',
      )) {
        excel.delete(
          'Sheet1',
        );
      }

      final bytes =
          excel.encode();

      if (bytes == null) {
        throw Exception(
          'Falha ao gerar Excel.',
        );
      }

      final pasta =
          await getTemporaryDirectory();

      final arq =
          File(
        '${pasta.path}/'
        'Faturas_Itau_conferidas.xlsx',
      );

      await arq.writeAsBytes(
        bytes,
      );

      await Share.shareXFiles(
        [
          XFile(
            arq.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content:
                Text(
              'Erro ao gerar Excel: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          gerandoExcel =
              false;
        });
      }
    }
  }

  String dinheiro(
    double valor,
  ) {
    final negativo =
        valor < 0;

    final partes =
        valor
            .abs()
            .toStringAsFixed(2)
            .split('.');

    final inteiro =
        partes[0];

    final b =
        StringBuffer();

    for (var i = 0;
        i < inteiro.length;
        i++) {
      final restante =
          inteiro.length - i;

      b.write(
        inteiro[i],
      );

      if (restante > 1 &&
          restante % 3 == 1) {
        b.write('.');
      }
    }

    return '${negativo ? '-' : ''}'
        'R\$ ${b.toString()},'
        '${partes[1]}';
  }

  Widget linha(
    String nome,
    String valor,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child:
                Text(nome),
          ),
          const SizedBox(
            width: 8,
          ),
          Flexible(
            child: Text(
              valor,
              textAlign:
                  TextAlign.right,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color cor(
    ResultadoFatura r,
  ) {
    if (r.conciliada) {
      return Colors.green;
    }

    if (r.falhaLeitura) {
      return Colors.red;
    }

    return Colors.orange;
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Conferidor de Faturas',
        ),
      ),
      body:
          ListView(
        padding:
            const EdgeInsets.all(
          20,
        ),
        children: [
          FilledButton.icon(
            onPressed:
                processando
                    ? null
                    : selecionarFaturas,
            icon:
                const Icon(
              Icons.picture_as_pdf,
            ),
            label:
                const Text(
              'Selecionar faturas PDF',
            ),
          ),

          const SizedBox(
            height: 15,
          ),

          if (processando)
            const LinearProgressIndicator(),

          Card(
            child:
                Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child:
                  Text(status),
            ),
          ),

          if (faturas.isNotEmpty) ...[
            const SizedBox(
              height: 15,
            ),

            Card(
              child:
                  Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child:
                    Column(
                  children: [
                    linha(
                      'Faturas processadas',
                      '${faturas.length}',
                    ),
                    linha(
                      'Conciliadas',
                      '$conciliadas',
                    ),
                    linha(
                      'Incompletas',
                      '$incompletas',
                    ),
                    linha(
                      'Divergentes',
                      '$divergentes',
                    ),
                    linha(
                      'Falhas',
                      '$falhas',
                    ),
                    const Divider(),
                    linha(
                      'Total das faturas',
                      dinheiro(
                        totalFaturas,
                      ),
                    ),
                    linha(
                      'Soma dos lançamentos',
                      dinheiro(
                        totalLancamentos,
                      ),
                    ),
                    linha(
                      'Compras reconstruídas',
                      '$compras',
                    ),
                    linha(
                      'Compras parceladas',
                      '$parceladas',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            FilledButton.icon(
              onPressed:
                  gerandoDiagnostico
                      ? null
                      : gerarDiagnosticoTotal,
              icon:
                  const Icon(
                Icons.bug_report,
              ),
              label:
                  Text(
                gerandoDiagnostico
                    ? 'Gerando diagnóstico...'
                    : 'Gerar diagnóstico total',
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            FilledButton.icon(
              onPressed:
                  todasConciliadas &&
                          !gerandoExcel
                      ? gerarExcel
                      : null,
              icon:
                  const Icon(
                Icons.table_view,
              ),
              label:
                  Text(
                gerandoExcel
                    ? 'Gerando Excel...'
                    : todasConciliadas
                        ? 'Gerar Excel consolidado'
                        : 'Excel bloqueado - existem divergências',
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            ...faturas.map(
              (f) {
                final r =
                    f.resultado;

                return Card(
                  margin:
                      const EdgeInsets.symmetric(
                    vertical: 7,
                  ),
                  child:
                      Padding(
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.arquivo,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        Text(
                          'Estratégia: ${r.estrategia}',
                        ),

                        if (r.vencimento.isNotEmpty)
                          Text(
                            'Vencimento: ${r.vencimento}',
                          ),

                        if (r.cartao.isNotEmpty)
                          Text(
                            'Cartão: ${r.cartao}',
                          ),

                        const SizedBox(
                          height: 10,
                        ),

                        linha(
                          'Total da fatura',
                          r.totalFatura == null
                              ? 'Não identificado'
                              : dinheiro(
                                  r.totalFatura!,
                                ),
                        ),

                        linha(
                          'Subtotal cartão',
                          r.totalCartaoInformado == null
                              ? 'Não identificado'
                              : dinheiro(
                                  r.totalCartaoInformado!,
                                ),
                        ),

                        linha(
                          'Soma compras',
                          dinheiro(
                            r.somaCompras,
                          ),
                        ),

                        linha(
                          'Diferença cartão',
                          r.diferencaCartao == null
                              ? 'Não calculada'
                              : dinheiro(
                                  r.diferencaCartao!,
                                ),
                        ),

                        if (r.totalInternacionalInformado != null)
                          linha(
                            'Internacional',
                            dinheiro(
                              r.totalInternacionalInformado!,
                            ),
                          ),

                        if (r.totalServicosInformado != null)
                          linha(
                            'Produtos/serviços',
                            dinheiro(
                              r.totalServicosInformado!,
                            ),
                          ),

                        if (r.totalEncargosInformado != null)
                          linha(
                            'Encargos',
                            dinheiro(
                              r.totalEncargosInformado!,
                            ),
                          ),

                        const Divider(),

                        linha(
                          'Soma geral',
                          dinheiro(
                            r.soma,
                          ),
                        ),

                        linha(
                          'Diferença geral',
                          r.diferenca == null
                              ? 'Não calculada'
                              : dinheiro(
                                  r.diferenca!,
                                ),
                        ),

                        linha(
                          'Compras',
                          '${r.compras.length}',
                        ),

                        linha(
                          'Parceladas',
                          '${r.quantidadeParceladas}',
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Row(
                          children: [
                            Icon(
                              r.conciliada
                                  ? Icons.check_circle
                                  : r.falhaLeitura
                                      ? Icons.error
                                      : Icons.warning_amber,
                              color:
                                  cor(r),
                            ),

                            const SizedBox(
                              width: 8,
                            ),

                            Text(
                              r.status,
                              style:
                                  TextStyle(
                                color:
                                    cor(r),
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        if (r.alertas.isNotEmpty) ...[
                          const SizedBox(
                            height: 8,
                          ),

                          ...r.alertas.map(
                            (a) =>
                                Padding(
                              padding:
                                  const EdgeInsets.only(
                                bottom: 3,
                              ),
                              child:
                                  Text(
                                '• $a',
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(
                          height: 10,
                        ),

                        OutlinedButton.icon(
                          onPressed:
                              () =>
                                  gerarDiagnostico(
                            f,
                          ),
                          icon:
                              const Icon(
                            Icons.description,
                          ),
                          label:
                              const Text(
                            'Gerar diagnóstico desta fatura',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
