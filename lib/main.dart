import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const ConferidorApp());
}

// ============================================================
// MODELOS
// ============================================================

class Lancamento {
  final String data;
  final String descricao;
  final String categoria;
  final double valor;
  final int? parcelaAtual;
  final int? totalParcelas;
  final String tipo;
  final String observacoes;

  Lancamento({
    required this.data,
    required this.descricao,
    required this.categoria,
    required this.valor,
    required this.tipo,
    this.parcelaAtual,
    this.totalParcelas,
    this.observacoes = '',
  });

  bool get parcelada =>
      parcelaAtual != null && totalParcelas != null;
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

  final List<Lancamento> lancamentos;
  final List<Lancamento> compras;
  final List<String> alertas;

  ResultadoFatura({
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
    this.alertas = const [],
  });

  double get soma {
    return lancamentos.fold<double>(
      0,
      (s, e) => s + e.valor,
    );
  }

  double get somaCompras {
    return compras.fold<double>(
      0,
      (s, e) => s + e.valor,
    );
  }

  double? get diferenca {
    if (totalFatura == null) return null;
    return totalFatura! - soma;
  }

  double? get diferencaCartao {
    if (totalCartaoInformado == null) return null;
    return totalCartaoInformado! - somaCompras;
  }

  int get quantidadeParceladas {
    return compras.where((e) => e.parcelada).length;
  }

  bool get comprasConciliadas {
    if (totalCartaoInformado == null) {
      return compras.isNotEmpty;
    }

    return (totalCartaoInformado! - somaCompras).abs() < 0.02;
  }

  bool get totalConciliado {
    if (totalFatura == null) return false;

    return (totalFatura! - soma).abs() < 0.02;
  }

  bool get conciliada {
    return totalConciliado && comprasConciliadas;
  }

  bool get falhaLeitura {
    return totalFatura == null &&
        totalCartaoInformado == null &&
        compras.isEmpty;
  }

  String get status {
    if (falhaLeitura) {
      return 'FALHA DE LEITURA';
    }

    if (conciliada) {
      return 'CONCILIADA';
    }

    if (totalConciliado && !comprasConciliadas) {
      return 'INCOMPLETA';
    }

    return 'DIVERGENTE';
  }
}

class FaturaProcessada {
  final String arquivo;
  final ResultadoFatura resultado;

  final String textoLayout;
  final String textoBruto;

  final String parserEscolhido;

  FaturaProcessada({
    required this.arquivo,
    required this.resultado,
    required this.textoLayout,
    required this.textoBruto,
    required this.parserEscolhido,
  });
}

// ============================================================
// PARSER ITAÚ V6
// ============================================================

class ParserItau {
  // ==========================================================
  // NORMALIZAÇÃO
  // ==========================================================

  static String semAcentos(String texto) {
    return texto
        .replaceAll(RegExp('[áàãâäÁÀÃÂÄ]'), 'a')
        .replaceAll(RegExp('[éèêëÉÈÊË]'), 'e')
        .replaceAll(RegExp('[íìîïÍÌÎÏ]'), 'i')
        .replaceAll(RegExp('[óòõôöÓÒÕÔÖ]'), 'o')
        .replaceAll(RegExp('[úùûüÚÙÛÜ]'), 'u')
        .replaceAll(RegExp('[çÇ]'), 'c');
  }

  static String limparEspacos(String texto) {
    return texto
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static String compactar(String texto) {
    return semAcentos(texto)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
  }

  static double moedaParaDouble(String valor) {
    var t = valor
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    final negativo = t.startsWith('-');

    if (negativo) {
      t = t.substring(1);
    }

    t = t.replaceAll('.', '').replaceAll(',', '.');

    final n = double.tryParse(t) ?? 0.0;

    return negativo ? -n : n;
  }

  static bool dataValida(String data) {
    final p = data.split('/');

    if (p.length != 2) return false;

    final dia = int.tryParse(p[0]);
    final mes = int.tryParse(p[1]);

    if (dia == null || mes == null) return false;

    return dia >= 1 &&
        dia <= 31 &&
        mes >= 1 &&
        mes <= 12;
  }

  // ==========================================================
  // NÚMEROS ESPAÇADOS
  // Exemplo:
  // 1 1.4 81,9 4 -> 11.481,94
  // 1 50,00      -> 150,00
  // ==========================================================

  static String removerEspacosInternosNumero(String texto) {
    var anterior = '';

    var atual = texto;

    while (anterior != atual) {
      anterior = atual;

      atual = atual.replaceAllMapped(
        RegExp(r'(\d)[ \t]+(?=\d)'),
        (m) => m.group(1)!,
      );

      atual = atual.replaceAllMapped(
        RegExp(r'(\d)[ \t]+(?=[\.,])'),
        (m) => m.group(1)!,
      );

      atual = atual.replaceAllMapped(
        RegExp(r'([\.,])[ \t]+(?=\d)'),
        (m) => m.group(1)!,
      );
    }

    return atual;
  }

  static String normalizarLinha(String linha) {
    return limparEspacos(
      removerEspacosInternosNumero(linha),
    );
  }

  // ==========================================================
  // TOTAIS
  // ==========================================================

  static double? procurarSubtotal(
    String texto,
    List<String> marcadores,
  ) {
    final c = compactar(texto);

    for (final marcador in marcadores) {
      final alvo = compactar(marcador);

      final pos = c.indexOf(alvo);

      if (pos < 0) continue;

      final depois = c.substring(
        pos + alvo.length,
      );

      final m = RegExp(
        r'-?[\d\.]+,\d{2}',
      ).firstMatch(depois);

      if (m != null) {
        return moedaParaDouble(m.group(0)!);
      }
    }

    return null;
  }

  static double? procurarTotalFatura(String texto) {
    return procurarSubtotal(
      texto,
      const [
        'Total desta fatura',
        'Total da fatura',
      ],
    );
  }

  static String procurarVencimento(String texto) {
    final normalizado =
        removerEspacosInternosNumero(texto);

    final m = RegExp(
      r'vencimento\s*:?\s*(\d{2}/\d{2}/\d{4})',
      caseSensitive: false,
    ).firstMatch(normalizado);

    return m?.group(1) ?? '';
  }

  static String procurarCartao(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    for (final original in linhas) {
      final linha = normalizarLinha(original);

      if (!semAcentos(linha)
          .toLowerCase()
          .contains('cartao')) {
        continue;
      }

      final m = RegExp(
        r'cart[aã]o\s+([0-9xX\.\s]{8,})',
        caseSensitive: false,
      ).firstMatch(linha);

      if (m != null) {
        return limparEspacos(m.group(1)!);
      }
    }

    return '';
  }

  // ==========================================================
  // CATEGORIAS
  // ==========================================================

  static const categorias = <String>[
    'restaurante',
    'supermercado',
    'vestuario',
    'vestuário',
    'saude',
    'saúde',
    'servicos',
    'serviços',
    'outros',
    'lazer',
    'eletronicos',
    'eletrônicos',
    'hotel',
    'transporte',
    'viagem',
    'educacao',
    'educação',
    'health',
    'money',
    'supermarket',
    'automobile',
    'automóvel',
  ];

  static String normalizarCategoria(String valor) {
    final c = semAcentos(valor).toLowerCase().trim();

    const mapa = <String, String>{
      'vestuario': 'vestuário',
      'saude': 'saúde',
      'servicos': 'serviços',
      'educacao': 'educação',
      'eletronicos': 'eletrônicos',
      'supermarket': 'supermercado',
      'health': 'saúde',
      'money': 'serviços',
      'automobile': 'automóvel',
    };

    return mapa[c] ?? c;
  }

  static String detectarCategoria(String texto) {
    final c = compactar(texto);

    for (final categoria in categorias) {
      final cat = compactar(categoria);

      if (c.startsWith(cat)) {
        return normalizarCategoria(categoria);
      }
    }

    return 'outros';
  }

  // ==========================================================
  // IDENTIFICAÇÃO DE ÁREAS QUE NÃO SÃO COMPRAS ATUAIS
  // ==========================================================

  static bool ehTextoIgnorado(String texto) {
    final c = compactar(texto);

    return c.contains('pagamentoefetuado') ||
        c.contains('totaldospagamentos') ||
        c.contains('comprasparceladas-proximasfaturas') ||
        c.contains('comprasparceladasproximasfaturas') ||
        c.contains('proximafatura') ||
        c.contains('demaisfaturas') ||
        c.contains('totalparaproximasfaturas') ||
        c.contains('limitedecredito') ||
        c.contains('limitestotal') ||
        c.contains('simulacaodecompras') ||
        c.contains('encargoscobradosnestafatura');
  }

  // ==========================================================
  // EXTRAÇÃO DE TRANSAÇÕES DE UM TRECHO
  // ==========================================================

  static List<Lancamento> extrairTransacoes(String trecho) {
    final resultado = <Lancamento>[];

    final texto = removerEspacosInternosNumero(
      trecho.replaceAll('\r', '\n'),
    );

    // Procura cada data DD/MM.
    //
    // A estratégia não depende de a compra estar no começo da
    // linha, pois algumas páginas do Itaú têm duas colunas.
    final datas = RegExp(
      r'(?<!\d)(\d{2}/\d{2})(?!\d)',
    ).allMatches(texto).toList();

    for (var i = 0; i < datas.length; i++) {
      final dm = datas[i];

      final data = dm.group(1)!;

      if (!dataValida(data)) continue;

      final inicio = dm.end;

      final fim = i + 1 < datas.length
          ? datas[i + 1].start
          : texto.length;

      var bloco = texto.substring(inicio, fim);

      bloco = limparEspacos(
        bloco.replaceAll('\n', ' '),
      );

      if (bloco.isEmpty) continue;

      if (ehTextoIgnorado(bloco)) continue;

      // Valores monetários existentes no bloco.
      final valores = RegExp(
        r'-?\d[\d\.]*,\d{2}',
      ).allMatches(bloco).toList();

      if (valores.isEmpty) continue;

      // O primeiro valor monetário após a data é normalmente
      // o valor da transação no layout sequencial.
      //
      // Nos blocos reconstruídos, evitamos usar valores
      // claramente pertencentes a totais ou textos seguintes.
      final vm = valores.first;

      final valorTexto = vm.group(0)!;
      final valor = moedaParaDouble(valorTexto);

      if (valor.abs() > 100000) continue;

      var descricao = limparEspacos(
        bloco.substring(0, vm.start),
      );

      if (descricao.isEmpty) continue;

      // ------------------------------------------------------
      // PARCELA
      // ------------------------------------------------------

      int? parcelaAtual;
      int? totalParcelas;

      final parcela = RegExp(
        r'(\d{1,2})/(\d{1,2})\s*$',
      ).firstMatch(descricao);

      if (parcela != null) {
        final atual = int.tryParse(parcela.group(1)!);
        final total = int.tryParse(parcela.group(2)!);

        if (atual != null &&
            total != null &&
            atual >= 1 &&
            total >= atual &&
            total <= 60) {
          parcelaAtual = atual;
          totalParcelas = total;

          descricao = limparEspacos(
            descricao.substring(
              0,
              parcela.start,
            ),
          );
        }
      }

      if (descricao.isEmpty) continue;

      // Impede que cabeçalhos sejam interpretados como compra.
      final dc = compactar(descricao);

      if (dc.contains('valoremr') ||
          dc.contains('estabelecimento') ||
          dc.startsWith('pagamento') ||
          dc.contains('totaldos')) {
        continue;
      }

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: 'outros',
          valor: valor,
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
          tipo: parcelaAtual != null
              ? 'Parcelada'
              : 'À vista',
          observacoes: 'Parser v6',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // COMPRAS - ESTRATÉGIA POR LINHAS
  // ==========================================================

  static List<Lancamento> lerComprasLinhas(String texto) {
    final linhas = texto.replaceAll('\r', '').split('\n');

    final resultado = <Lancamento>[];

    bool dentroCompras = false;
    bool parar = false;

    final rx = RegExp(
      r'^\s*(\d{2}/\d{2})\s+(.+?)\s+(-?\d[\d\.]*,\d{2})\s*$',
    );

    for (var i = 0; i < linhas.length; i++) {
      final linha = normalizarLinha(linhas[i]);

      final c = compactar(linha);

      if (c.contains('lancamentos:comprasesaques') ||
          c.contains('lancamentoscomprasesaques')) {
        dentroCompras = true;
        parar = false;
        continue;
      }

      if (!dentroCompras || parar) continue;

      if (c.contains('lancamentosinternacionais') ||
          c.contains('lancamentos:produtoseservicos') ||
          c.contains('lancamentosprodutoseservicos') ||
          c.contains('comprasparceladas-proximasfaturas') ||
          c.contains('comprasparceladasproximasfaturas') ||
          c.contains('lancamentosnocartao')) {
        parar = true;
        continue;
      }

      final m = rx.firstMatch(linha);

      if (m == null) continue;

      final data = m.group(1)!;

      if (!dataValida(data)) continue;

      var descricao = limparEspacos(m.group(2)!);

      final valor = moedaParaDouble(m.group(3)!);

      if (valor.abs() > 100000) continue;

      int? parcelaAtual;
      int? totalParcelas;

      final pm = RegExp(
        r'(\d{1,2})/(\d{1,2})\s*$',
      ).firstMatch(descricao);

      if (pm != null) {
        final pa = int.tryParse(pm.group(1)!);
        final pt = int.tryParse(pm.group(2)!);

        if (pa != null &&
            pt != null &&
            pa >= 1 &&
            pt >= pa &&
            pt <= 60) {
          parcelaAtual = pa;
          totalParcelas = pt;

          descricao = limparEspacos(
            descricao.substring(0, pm.start),
          );
        }
      }

      var categoria = 'outros';

      if (i + 1 < linhas.length) {
        categoria = detectarCategoria(
          normalizarLinha(linhas[i + 1]),
        );
      }

      resultado.add(
        Lancamento(
          data: data,
          descricao: descricao,
          categoria: categoria,
          valor: valor,
          parcelaAtual: parcelaAtual,
          totalParcelas: totalParcelas,
          tipo: parcelaAtual != null
              ? 'Parcelada'
              : 'À vista',
          observacoes: 'Leitura por linha - Parser v6',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // COMPRAS - FALLBACK DE SEÇÃO
  // ==========================================================

  static List<Lancamento> lerComprasSecao(String texto) {
    final c = compactar(texto);

    var inicio = c.indexOf('lancamentos:comprasesaques');

    if (inicio < 0) {
      inicio = c.indexOf('lancamentoscomprasesaques');
    }

    // O texto compactado serve somente para localizar.
    // Para preservar descrições, procuramos no texto normalizado.
    var normal = removerEspacosInternosNumero(texto);

    final nSem = semAcentos(normal).toLowerCase();

    var pos = nSem.indexOf('lancamentos: compras e saques');

    if (pos < 0) {
      pos = nSem.indexOf('lancamentos compras e saques');
    }

    if (pos < 0) {
      return [];
    }

    normal = normal.substring(pos);

    final candidatosFim = <String>[
      'lançamentos internacionais',
      'lancamentos internacionais',
      'lançamentos: produtos e serviços',
      'lancamentos: produtos e servicos',
      'compras parceladas - próximas faturas',
      'compras parceladas - proximas faturas',
      'lançamentos no cartão',
      'lancamentos no cartao',
    ];

    var fim = normal.length;

    final normalLower = semAcentos(normal).toLowerCase();

    for (final marcador in candidatosFim) {
      final p = normalLower.indexOf(
        semAcentos(marcador).toLowerCase(),
        20,
      );

      if (p >= 0 && p < fim) {
        fim = p;
      }
    }

    return extrairTransacoes(
      normal.substring(0, fim),
    );
  }

  // ==========================================================
  // ESCOLHA DA MELHOR LISTA DE COMPRAS
  // ==========================================================

  static List<Lancamento> lerCompras(
    String texto,
    double? totalCartao,
  ) {
    final a = lerComprasLinhas(texto);
    final b = lerComprasSecao(texto);

    if (totalCartao == null) {
      return a.length >= b.length ? a : b;
    }

    double erro(List<Lancamento> lista) {
      final soma = lista.fold<double>(
        0,
        (s, e) => s + e.valor,
      );

      return (totalCartao - soma).abs();
    }

    final ea = erro(a);
    final eb = erro(b);

    if (ea < 0.02) return a;
    if (eb < 0.02) return b;

    return ea <= eb ? a : b;
  }

  // ==========================================================
  // INTERNACIONAL
  // ==========================================================

  static List<Lancamento> lerInternacional(String texto) {
    final resultado = <Lancamento>[];

    final transacoes = procurarSubtotal(
      texto,
      const [
        'Total transações inter. em R\$',
        'Total transacoes inter. em R\$',
      ],
    );

    final iof = procurarSubtotal(
      texto,
      const [
        'Repasse de IOF em R\$',
        'Repasse de IOF',
      ],
    );

    if (transacoes != null && transacoes.abs() >= 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'Transações internacionais',
          categoria: 'internacional',
          valor: transacoes,
          tipo: 'Internacional',
          observacoes:
              'Subtotal oficial de transações internacionais',
        ),
      );
    }

    if (iof != null && iof.abs() >= 0.001) {
      resultado.add(
        Lancamento(
          data: '',
          descricao: 'IOF - transações internacionais',
          categoria: 'encargos',
          valor: iof,
          tipo: 'IOF internacional',
          observacoes: 'IOF internacional informado na fatura',
        ),
      );
    }

    return resultado;
  }

  // ==========================================================
  // PRODUTOS E SERVIÇOS
  // ==========================================================

  static List<Lancamento> lerProdutosServicos(
    String texto,
    double? subtotal,
  ) {
    if (subtotal == null || subtotal.abs() < 0.001) {
      return [];
    }

    return [
      Lancamento(
        data: '',
        descricao: 'Produtos e serviços',
        categoria: 'produtos e serviços',
        valor: subtotal,
        tipo: 'Produto/Serviço',
        observacoes:
            'Subtotal oficial de produtos e serviços',
      ),
    ];
  }

  // ==========================================================
  // ENCARGOS
  // ==========================================================

  static List<Lancamento> lerEncargos(double? total) {
    if (total == null || total.abs() < 0.001) {
      return [];
    }

    return [
      Lancamento(
        data: '',
        descricao: 'Encargos cobrados nesta fatura',
        categoria: 'encargos',
        valor: total,
        tipo: 'Encargo financeiro',
        observacoes: 'Subtotal oficial de encargos',
      ),
    ];
  }

  // ==========================================================
  // SALDO FINANCIADO
  // ==========================================================

  static List<Lancamento> lerSaldoFinanciado(double? saldo) {
    if (saldo == null || saldo.abs() < 0.001) {
      return [];
    }

    return [
      Lancamento(
        data: '',
        descricao: 'Saldo financiado',
        categoria: 'financeiro',
        valor: saldo,
        tipo: 'Saldo financiado',
        observacoes:
            'Saldo financiado informado no resumo da fatura',
      ),
    ];
  }

  // ==========================================================
  // PROCESSAMENTO
  // ==========================================================

  static ResultadoFatura processar(String texto) {
    final alertas = <String>[];

    final totalFatura = procurarTotalFatura(texto);

    final totalCartao = procurarSubtotal(
      texto,
      const [
        'Lançamentos no cartão',
        'Lancamentos no cartao',
      ],
    );

    final totalInternacional = procurarSubtotal(
      texto,
      const [
        'Total lançamentos inter. em R\$',
        'Total lancamentos inter. em R\$',
      ],
    );

    final totalServicos = procurarSubtotal(
      texto,
      const [
        'Lançamentos produtos e serviços',
        'Lancamentos produtos e servicos',
      ],
    );

    final totalLancamentosAtuais = procurarSubtotal(
      texto,
      const [
        'Total dos lançamentos atuais',
        'Total dos lancamentos atuais',
      ],
    );

    final totalEncargos = procurarSubtotal(
      texto,
      const [
        'Total de encargos em R\$',
        'Total de encargos',
      ],
    );

    final saldoFinanciado = procurarSubtotal(
      texto,
      const [
        'Saldo financiado',
      ],
    );

    final compras = lerCompras(
      texto,
      totalCartao,
    );

    final internacional = lerInternacional(texto);

    final produtos = lerProdutosServicos(
      texto,
      totalServicos,
    );

    final encargos = lerEncargos(
      totalEncargos,
    );

    final saldo = lerSaldoFinanciado(
      saldoFinanciado,
    );

    final somaCompras = compras.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    // ========================================================
    // VALIDAÇÃO DO CARTÃO
    // ========================================================

    if (totalCartao != null) {
      final diferenca = totalCartao - somaCompras;

      if (diferenca.abs() >= 0.02) {
        alertas.add(
          'Compras individuais não fecham "Lançamentos no cartão". '
          'Diferença: R\$ ${diferenca.toStringAsFixed(2)}',
        );
      }
    } else {
      alertas.add(
        'Subtotal "Lançamentos no cartão" não identificado.',
      );
    }

    if (compras.isEmpty) {
      alertas.add(
        'Nenhuma compra individual válida foi reconstruída.',
      );
    }

    // ========================================================
    // LANÇAMENTOS ATUAIS
    // ========================================================

    final componentesAtuais = <Lancamento>[
      ...compras,
      ...internacional,
      ...produtos,
    ];

    final somaAtuais = componentesAtuais.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (totalLancamentosAtuais != null) {
      final diferenca = totalLancamentosAtuais - somaAtuais;

      if (diferenca.abs() >= 0.02) {
        alertas.add(
          'Componentes dos lançamentos atuais não fecham o subtotal oficial. '
          'Diferença: R\$ ${diferenca.toStringAsFixed(2)}',
        );
      }
    }

    // ========================================================
    // TOTAL
    // ========================================================

    final lancamentos = <Lancamento>[
      ...componentesAtuais,
      ...encargos,
      ...saldo,
    ];

    final somaFinal = lancamentos.fold<double>(
      0,
      (s, e) => s + e.valor,
    );

    if (totalFatura == null) {
      alertas.add(
        'Total da fatura não identificado.',
      );
    } else {
      final diferenca = totalFatura - somaFinal;

      if (diferenca.abs() >= 0.02) {
        alertas.add(
          'Total da fatura não conciliado. '
          'Diferença: R\$ ${diferenca.toStringAsFixed(2)}',
        );
      }
    }

    // ========================================================
    // INTERNACIONAL
    // ========================================================

    if (totalInternacional != null) {
      final somaInternacional = internacional.fold<double>(
        0,
        (s, e) => s + e.valor,
      );

      final diferenca =
          totalInternacional - somaInternacional;

      if (diferenca.abs() >= 0.02) {
        alertas.add(
          'Subtotal internacional não conciliado. '
          'Diferença: R\$ ${diferenca.toStringAsFixed(2)}',
        );
      }
    }

    return ResultadoFatura(
      totalFatura: totalFatura,
      totalCartaoInformado: totalCartao,
      totalInternacionalInformado: totalInternacional,
      totalServicosInformado: totalServicos,
      totalLancamentosAtuaisInformado:
          totalLancamentosAtuais,
      totalEncargosInformado: totalEncargos,
      saldoFinanciadoInformado: saldoFinanciado,
      vencimento: procurarVencimento(texto),
      cartao: procurarCartao(texto),
      lancamentos: lancamentos,
      compras: compras,
      alertas: alertas,
    );
  }
}

// ============================================================
// APP
// ============================================================

class ConferidorApp extends StatelessWidget {
  const ConferidorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Conferidor de Faturas',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool processando = false;
  bool gerandoExcel = false;
  bool gerandoDiagnostico = false;

  String status =
      'Selecione uma ou mais faturas Itaú em PDF.';

  final List<FaturaProcessada> faturas = [];

  // ==========================================================
  // RESUMOS
  // ==========================================================

  int get quantidadeConciliadas {
    return faturas.where((f) => f.resultado.conciliada).length;
  }

  int get quantidadeDivergentes {
    return faturas
        .where((f) => f.resultado.status == 'DIVERGENTE')
        .length;
  }

  int get quantidadeIncompletas {
    return faturas
        .where((f) => f.resultado.status == 'INCOMPLETA')
        .length;
  }

  int get quantidadeFalhas {
    return faturas
        .where((f) => f.resultado.falhaLeitura)
        .length;
  }

  int get totalLancamentos {
    return faturas.fold<int>(
      0,
      (s, f) => s + f.resultado.lancamentos.length,
    );
  }

  int get totalCompras {
    return faturas.fold<int>(
      0,
      (s, f) => s + f.resultado.compras.length,
    );
  }

  int get totalParceladas {
    return faturas.fold<int>(
      0,
      (s, f) => s + f.resultado.quantidadeParceladas,
    );
  }

  double get valorTotalFaturas {
    return faturas.fold<double>(
      0,
      (s, f) => s + (f.resultado.totalFatura ?? 0),
    );
  }

  double get somaTotalLancamentos {
    return faturas.fold<double>(
      0,
      (s, f) => s + f.resultado.soma,
    );
  }

  bool get todasConciliadas {
    return faturas.isNotEmpty &&
        faturas.every((f) => f.resultado.conciliada);
  }

  // ==========================================================
  // ESCOLHA DO MELHOR RESULTADO
  // ==========================================================

  ResultadoFatura escolherMelhor(
    ResultadoFatura a,
    ResultadoFatura b,
  ) {
    if (a.conciliada != b.conciliada) {
      return a.conciliada ? a : b;
    }

    final erroCartaoA =
        a.diferencaCartao?.abs() ?? double.infinity;

    final erroCartaoB =
        b.diferencaCartao?.abs() ?? double.infinity;

    if ((erroCartaoA - erroCartaoB).abs() > 0.01) {
      return erroCartaoA < erroCartaoB ? a : b;
    }

    if (a.compras.length != b.compras.length) {
      return a.compras.length > b.compras.length ? a : b;
    }

    final erroA = a.diferenca?.abs() ?? double.infinity;
    final erroB = b.diferenca?.abs() ?? double.infinity;

    return erroA <= erroB ? a : b;
  }

  // ==========================================================
  // PROCESSAR PDFs
  // ==========================================================

  Future<void> selecionarFaturas() async {
    final escolha = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );

    if (escolha == null || escolha.files.isEmpty) {
      return;
    }

    setState(() {
      processando = true;
      faturas.clear();
      status = 'Iniciando processamento...';
    });

    for (var i = 0; i < escolha.files.length; i++) {
      final arquivo = escolha.files[i];

      setState(() {
        status =
            'Analisando ${i + 1} de ${escolha.files.length}\n'
            '${arquivo.name}';
      });

      try {
        if (arquivo.path == null) {
          throw Exception('Arquivo sem caminho local.');
        }

        final bytes = await File(
          arquivo.path!,
        ).readAsBytes();

        final documento = PdfDocument(
          inputBytes: bytes,
        );

        final extrator = PdfTextExtractor(documento);

        final textoBruto = extrator.extractText();

        final textoLayout = extrator.extractText(
          layoutText: true,
        );

        documento.dispose();

        final resultadoLayout = ParserItau.processar(
          textoLayout,
        );

        final resultadoBruto = ParserItau.processar(
          textoBruto,
        );

        final resultado = escolherMelhor(
          resultadoLayout,
          resultadoBruto,
        );

        final parserEscolhido =
            identical(resultado, resultadoLayout)
                ? 'LAYOUT'
                : 'BRUTO';

        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            resultado: resultado,
            textoLayout: textoLayout,
            textoBruto: textoBruto,
            parserEscolhido: parserEscolhido,
          ),
        );
      } catch (e) {
        faturas.add(
          FaturaProcessada(
            arquivo: arquivo.name,
            textoLayout: '',
            textoBruto: '',
            parserEscolhido: 'ERRO',
            resultado: ResultadoFatura(
              totalFatura: null,
              lancamentos: const [],
              compras: const [],
              alertas: [
                'Falha ao processar arquivo: $e',
              ],
            ),
          ),
        );
      }
    }

    if (!mounted) return;

    setState(() {
      processando = false;

      status =
          '${faturas.length} fatura(s) processada(s).\n'
          '$quantidadeConciliadas conciliada(s), '
          '$quantidadeIncompletas incompleta(s), '
          '$quantidadeDivergentes divergente(s), '
          '$quantidadeFalhas falha(s).';
    });
  }

  // ==========================================================
  // TEXTO DE DIAGNÓSTICO DE UMA FATURA
  // ==========================================================

  String montarDiagnosticoFatura(
    FaturaProcessada fatura, {
    bool incluirTextos = true,
  }) {
    final r = fatura.resultado;

    final b = StringBuffer();

    b.writeln(
      '============================================================',
    );
    b.writeln('DIAGNÓSTICO - CONFERIDOR DE FATURAS ITAÚ');
    b.writeln('Parser: v6');
    b.writeln('Arquivo: ${fatura.arquivo}');
    b.writeln('Fonte escolhida: ${fatura.parserEscolhido}');
    b.writeln('Status: ${r.status}');
    b.writeln('Vencimento: ${r.vencimento}');
    b.writeln('Cartão: ${r.cartao}');
    b.writeln();

    b.writeln('===== CONFERÊNCIA =====');

    b.writeln('Total da fatura: ${r.totalFatura}');
    b.writeln('Subtotal cartão: ${r.totalCartaoInformado}');
    b.writeln('Soma compras: ${r.somaCompras}');
    b.writeln('Diferença cartão: ${r.diferencaCartao}');
    b.writeln(
      'Total internacional: ${r.totalInternacionalInformado}',
    );
    b.writeln(
      'Produtos/serviços: ${r.totalServicosInformado}',
    );
    b.writeln(
      'Total lançamentos atuais: '
      '${r.totalLancamentosAtuaisInformado}',
    );
    b.writeln('Encargos: ${r.totalEncargosInformado}');
    b.writeln(
      'Saldo financiado: ${r.saldoFinanciadoInformado}',
    );
    b.writeln('Soma geral: ${r.soma}');
    b.writeln('Diferença geral: ${r.diferenca}');
    b.writeln('Compras: ${r.compras.length}');
    b.writeln('Parceladas: ${r.quantidadeParceladas}');
    b.writeln();

    b.writeln('===== ALERTAS =====');

    if (r.alertas.isEmpty) {
      b.writeln('Nenhum alerta.');
    } else {
      for (final alerta in r.alertas) {
        b.writeln('- $alerta');
      }
    }

    b.writeln();

    b.writeln('===== COMPRAS RECONSTRUÍDAS =====');

    if (r.compras.isEmpty) {
      b.writeln('Nenhuma compra reconstruída.');
    } else {
      for (final item in r.compras) {
        b.writeln(
          '${item.data} | '
          '${item.descricao} | '
          '${item.valor.toStringAsFixed(2)} | '
          '${item.parcelaAtual ?? ''}/'
          '${item.totalParcelas ?? ''} | '
          '${item.categoria}',
        );
      }
    }

    b.writeln();

    b.writeln('===== TODOS OS LANÇAMENTOS =====');

    if (r.lancamentos.isEmpty) {
      b.writeln('Nenhum lançamento.');
    } else {
      for (final item in r.lancamentos) {
        b.writeln(
          '${item.data} | '
          '${item.descricao} | '
          '${item.valor.toStringAsFixed(2)} | '
          '${item.tipo} | '
          '${item.categoria} | '
          '${item.observacoes}',
        );
      }
    }

    if (incluirTextos) {
      b.writeln();
      b.writeln('===== TEXTO COM LAYOUT =====');
      b.writeln(fatura.textoLayout);

      b.writeln();
      b.writeln('===== TEXTO BRUTO =====');
      b.writeln(fatura.textoBruto);
    }

    b.writeln();
    b.writeln(
      '============================================================',
    );

    return b.toString();
  }

  // ==========================================================
  // DIAGNÓSTICO INDIVIDUAL
  // ==========================================================

  Future<void> gerarDiagnostico(
    FaturaProcessada fatura,
  ) async {
    final texto = montarDiagnosticoFatura(
      fatura,
    );

    final pasta = await getTemporaryDirectory();

    final nome = fatura.arquivo.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );

    final arq = File(
      '${pasta.path}/diagnostico_$nome.txt',
    );

    await arq.writeAsString(texto);

    await Share.shareXFiles(
      [
        XFile(
          arq.path,
          mimeType: 'text/plain',
        ),
      ],
    );
  }

  // ==========================================================
  // DIAGNÓSTICO TOTAL
  // ==========================================================

  Future<void> gerarDiagnosticoTotal() async {
    if (faturas.isEmpty) return;

    setState(() {
      gerandoDiagnostico = true;
    });

    try {
      final b = StringBuffer();

      b.writeln(
        '============================================================',
      );
      b.writeln(
        'DIAGNÓSTICO TOTAL - CONFERIDOR DE FATURAS ITAÚ',
      );
      b.writeln('Parser: v6');
      b.writeln(
        '============================================================',
      );
      b.writeln();

      b.writeln('===== RESUMO GERAL =====');
      b.writeln('Faturas processadas: ${faturas.length}');
      b.writeln('Conciliadas: $quantidadeConciliadas');
      b.writeln('Incompletas: $quantidadeIncompletas');
      b.writeln('Divergentes: $quantidadeDivergentes');
      b.writeln('Falhas de leitura: $quantidadeFalhas');
      b.writeln('Compras reconstruídas: $totalCompras');
      b.writeln('Lançamentos totais: $totalLancamentos');
      b.writeln('Compras parceladas: $totalParceladas');
      b.writeln('Valor total das faturas: $valorTotalFaturas');
      b.writeln(
        'Soma total dos lançamentos: $somaTotalLancamentos',
      );
      b.writeln();

      b.writeln('===== ÍNDICE DAS FATURAS =====');

      for (var i = 0; i < faturas.length; i++) {
        final f = faturas[i];
        final r = f.resultado;

        b.writeln(
          '${i + 1}. ${f.arquivo} | '
          '${r.status} | '
          'Total: ${r.totalFatura} | '
          'Cartão: ${r.totalCartaoInformado} | '
          'Compras: ${r.somaCompras} | '
          'Dif. cartão: ${r.diferencaCartao} | '
          'Fonte: ${f.parserEscolhido}',
        );
      }

      b.writeln();
      b.writeln();
      b.writeln(
        '############################################################',
      );
      b.writeln(
        '# DETALHAMENTO COMPLETO DAS FATURAS',
      );
      b.writeln(
        '############################################################',
      );
      b.writeln();

      // Primeiro as divergentes para facilitar análise.
      final ordenadas = <FaturaProcessada>[
        ...faturas.where((f) => !f.resultado.conciliada),
        ...faturas.where((f) => f.resultado.conciliada),
      ];

      for (var i = 0; i < ordenadas.length; i++) {
        b.writeln();
        b.writeln(
          '############################################################',
        );
        b.writeln(
          '# FATURA ${i + 1} DE ${ordenadas.length}',
        );
        b.writeln(
          '############################################################',
        );

        b.writeln(
          montarDiagnosticoFatura(
            ordenadas[i],
            incluirTextos: true,
          ),
        );
      }

      final pasta = await getTemporaryDirectory();

      final agora = DateTime.now();

      final nome =
          'diagnostico_total_'
          '${agora.year}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_'
          '${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}'
          '${agora.second.toString().padLeft(2, '0')}.txt';

      final arq = File(
        '${pasta.path}/$nome',
      );

      await arq.writeAsString(
        b.toString(),
      );

      await Share.shareXFiles(
        [
          XFile(
            arq.path,
            mimeType: 'text/plain',
          ),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar diagnóstico total: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          gerandoDiagnostico = false;
        });
      }
    }
  }

  // ==========================================================
  // EXCEL
  // ==========================================================

  Future<void> gerarExcel() async {
    if (!todasConciliadas) return;

    setState(() {
      gerandoExcel = true;
    });

    try {
      final excel = Excel.createExcel();

      final sheet = excel['Lançamentos'];

      sheet.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Vencimento'),
        TextCellValue('Data'),
        TextCellValue('Descrição'),
        TextCellValue('Categoria'),
        TextCellValue('Valor'),
        TextCellValue('Parcela atual'),
        TextCellValue('Total parcelas'),
        TextCellValue('Tipo'),
        TextCellValue('Observações'),
      ]);

      for (final fatura in faturas) {
        for (final item in fatura.resultado.lancamentos) {
          sheet.appendRow([
            TextCellValue(fatura.arquivo),
            TextCellValue(fatura.resultado.vencimento),
            TextCellValue(item.data),
            TextCellValue(item.descricao),
            TextCellValue(item.categoria),
            DoubleCellValue(item.valor),
            item.parcelaAtual == null
                ? TextCellValue('')
                : IntCellValue(item.parcelaAtual!),
            item.totalParcelas == null
                ? TextCellValue('')
                : IntCellValue(item.totalParcelas!),
            TextCellValue(item.tipo),
            TextCellValue(item.observacoes),
          ]);
        }
      }

      final conf = excel['Conferência'];

      conf.appendRow([
        TextCellValue('Arquivo'),
        TextCellValue('Total fatura'),
        TextCellValue('Subtotal cartão'),
        TextCellValue('Soma compras'),
        TextCellValue('Diferença cartão'),
        TextCellValue('Internacional'),
        TextCellValue('Produtos/serviços'),
        TextCellValue('Lançamentos atuais'),
        TextCellValue('Encargos'),
        TextCellValue('Saldo financiado'),
        TextCellValue('Soma lançamentos'),
        TextCellValue('Diferença final'),
        TextCellValue('Compras'),
        TextCellValue('Parceladas'),
        TextCellValue('Fonte'),
        TextCellValue('Status'),
      ]);

      for (final fatura in faturas) {
        final r = fatura.resultado;

        conf.appendRow([
          TextCellValue(fatura.arquivo),
          DoubleCellValue(r.totalFatura ?? 0),
          DoubleCellValue(r.totalCartaoInformado ?? 0),
          DoubleCellValue(r.somaCompras),
          DoubleCellValue(r.diferencaCartao ?? 0),
          DoubleCellValue(
            r.totalInternacionalInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalServicosInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalLancamentosAtuaisInformado ?? 0,
          ),
          DoubleCellValue(
            r.totalEncargosInformado ?? 0,
          ),
          DoubleCellValue(
            r.saldoFinanciadoInformado ?? 0,
          ),
          DoubleCellValue(r.soma),
          DoubleCellValue(r.diferenca ?? 0),
          IntCellValue(r.compras.length),
          IntCellValue(r.quantidadeParceladas),
          TextCellValue(fatura.parserEscolhido),
          TextCellValue(r.status),
        ]);
      }

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes = excel.encode();

      if (bytes == null) {
        throw Exception('Falha ao gerar arquivo Excel.');
      }

      final pasta = await getTemporaryDirectory();

      final arq = File(
        '${pasta.path}/Faturas_Itau_conferidas.xlsx',
      );

      await arq.writeAsBytes(bytes);

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar Excel: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          gerandoExcel = false;
        });
      }
    }
  }

  // ==========================================================
  // FORMATAÇÃO
  // ==========================================================

  String dinheiro(double valor) {
    final negativo = valor < 0;

    final partes = valor
        .abs()
        .toStringAsFixed(2)
        .split('.');

    final inteiro = partes[0];

    final b = StringBuffer();

    for (var i = 0; i < inteiro.length; i++) {
      final restante = inteiro.length - i;

      b.write(inteiro[i]);

      if (restante > 1 && restante % 3 == 1) {
        b.write('.');
      }
    }

    return '${negativo ? '-' : ''}'
        'R\$ ${b.toString()},${partes[1]}';
  }

  Widget linha(
    String nome,
    String valor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(nome),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color corStatus(ResultadoFatura r) {
    if (r.conciliada) {
      return Colors.green;
    }

    if (r.falhaLeitura) {
      return Colors.red;
    }

    return Colors.orange;
  }

  // ==========================================================
  // INTERFACE
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Conferidor de Faturas',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed:
                processando ? null : selecionarFaturas,
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            label: const Text(
              'Selecionar faturas PDF',
            ),
          ),

          const SizedBox(height: 15),

          if (processando)
            const LinearProgressIndicator(),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(status),
            ),
          ),

          if (faturas.isNotEmpty) ...[
            const SizedBox(height: 15),

            // =================================================
            // RESUMO
            // =================================================

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    linha(
                      'Faturas processadas',
                      '${faturas.length}',
                    ),
                    linha(
                      'Conciliadas',
                      '$quantidadeConciliadas',
                    ),
                    linha(
                      'Incompletas',
                      '$quantidadeIncompletas',
                    ),
                    linha(
                      'Divergentes',
                      '$quantidadeDivergentes',
                    ),
                    linha(
                      'Falhas',
                      '$quantidadeFalhas',
                    ),
                    const Divider(),
                    linha(
                      'Total das faturas',
                      dinheiro(valorTotalFaturas),
                    ),
                    linha(
                      'Soma dos lançamentos',
                      dinheiro(somaTotalLancamentos),
                    ),
                    linha(
                      'Compras reconstruídas',
                      '$totalCompras',
                    ),
                    linha(
                      'Lançamentos totais',
                      '$totalLancamentos',
                    ),
                    linha(
                      'Compras parceladas',
                      '$totalParceladas',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            // =================================================
            // DIAGNÓSTICO TOTAL
            // =================================================

            FilledButton.icon(
              onPressed: gerandoDiagnostico
                  ? null
                  : gerarDiagnosticoTotal,
              icon: const Icon(
                Icons.bug_report,
              ),
              label: Text(
                gerandoDiagnostico
                    ? 'Gerando diagnóstico total...'
                    : 'Gerar diagnóstico total',
              ),
            ),

            const SizedBox(height: 10),

            // =================================================
            // EXCEL
            // =================================================

            FilledButton.icon(
              onPressed:
                  todasConciliadas && !gerandoExcel
                      ? gerarExcel
                      : null,
              icon: const Icon(
                Icons.table_view,
              ),
              label: Text(
                gerandoExcel
                    ? 'Gerando Excel...'
                    : todasConciliadas
                        ? 'Gerar Excel consolidado'
                        : 'Excel bloqueado - existem divergências',
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Conferência por fatura',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            // =================================================
            // CARDS DAS FATURAS
            // =================================================

            ...faturas.map(
              (fatura) {
                final r = fatura.resultado;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          fatura.arquivo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          'Fonte: ${fatura.parserEscolhido}',
                        ),

                        if (r.vencimento.isNotEmpty)
                          Text(
                            'Vencimento: ${r.vencimento}',
                          ),

                        if (r.cartao.isNotEmpty)
                          Text(
                            'Cartão: ${r.cartao}',
                          ),

                        const SizedBox(height: 12),

                        linha(
                          'Total da fatura',
                          r.totalFatura == null
                              ? 'Não identificado'
                              : dinheiro(r.totalFatura!),
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
                          'Soma das compras',
                          dinheiro(r.somaCompras),
                        ),

                        linha(
                          'Diferença cartão',
                          r.diferencaCartao == null
                              ? 'Não calculada'
                              : dinheiro(
                                  r.diferencaCartao!,
                                ),
                        ),

                        if (r.totalInternacionalInformado !=
                            null)
                          linha(
                            'Internacional + IOF',
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

                        if (r.totalLancamentosAtuaisInformado !=
                            null)
                          linha(
                            'Lançamentos atuais',
                            dinheiro(
                              r.totalLancamentosAtuaisInformado!,
                            ),
                          ),

                        if (r.totalEncargosInformado != null)
                          linha(
                            'Encargos',
                            dinheiro(
                              r.totalEncargosInformado!,
                            ),
                          ),

                        if (r.saldoFinanciadoInformado != null &&
                            r.saldoFinanciadoInformado!
                                    .abs() >
                                0.001)
                          linha(
                            'Saldo financiado',
                            dinheiro(
                              r.saldoFinanciadoInformado!,
                            ),
                          ),

                        const Divider(),

                        linha(
                          'Soma geral',
                          dinheiro(r.soma),
                        ),

                        linha(
                          'Diferença geral',
                          r.diferenca == null
                              ? 'Não calculada'
                              : dinheiro(r.diferenca!),
                        ),

                        linha(
                          'Compras individuais',
                          '${r.compras.length}',
                        ),

                        linha(
                          'Parceladas',
                          '${r.quantidadeParceladas}',
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Icon(
                              r.conciliada
                                  ? Icons.check_circle
                                  : r.falhaLeitura
                                      ? Icons.error
                                      : Icons.warning_amber,
                              color: corStatus(r),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              r.status,
                              style: TextStyle(
                                color: corStatus(r),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        if (r.alertas.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ...r.alertas.map(
                            (alerta) => Padding(
                              padding:
                                  const EdgeInsets.only(
                                bottom: 4,
                              ),
                              child: Text(
                                '• $alerta',
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: () {
                            gerarDiagnostico(fatura);
                          },
                          icon: const Icon(
                            Icons.description,
                          ),
                          label: const Text(
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
