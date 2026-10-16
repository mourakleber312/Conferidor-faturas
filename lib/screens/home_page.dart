part of '../main.dart';

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
  int novasSalvas = 0;
  int duplicadasEncontradas = 0;
  int falhasSalvamento = 0;

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
      novasSalvas = 0;
      duplicadasEncontradas = 0;
      falhasSalvamento = 0;
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

        // V23: captura palavras com bounds reais. O formato G é propositalmente
        // simples para ficar auditável no diagnóstico e independente do parser.
        final geometria = StringBuffer();
        for (var pagina = 0; pagina < pdf.pages.count; pagina++) {
          final linhasGeo = extrator.extractTextLines(
            startPageIndex: pagina,
            endPageIndex: pagina,
          );
          for (var li = 0; li < linhasGeo.length; li++) {
            final linhaGeo = linhasGeo[li];
            for (final palavra in linhaGeo.wordCollection) {
              final r = palavra.bounds;
              final t = palavra.text.replaceAll('\t', ' ').replaceAll('\n', ' ').replaceAll('\r', ' ');
              geometria.writeln(
                'G\t${pagina + 1}\t$li\t${r.left.toStringAsFixed(3)}\t${r.top.toStringAsFixed(3)}\t${r.width.toStringAsFixed(3)}\t${r.height.toStringAsFixed(3)}\t${palavra.fontSize.toStringAsFixed(2)}\t$t',
              );
            }
          }
        }
        final textoGeometrico = geometria.toString();

        pdf.dispose();

        final resultado =
            ParserItau.processar(
          bruto,
          layout,
          layoutPaginas,
          textoGeometrico,
        );

        final processada = FaturaProcessada(
            arquivo:
                arquivo.name,
            resultado:
                resultado,
            textoLayout:
                layout,
            textoLayoutPaginas:
                layoutPaginas,
            textoGeometrico:
                textoGeometrico,
            textoBruto:
                bruto,
          );
        faturas.add(processada);
        if (resultado.conciliada) {
          try {
            final salva = await HistoricoLocal.salvar(processada);
            if (salva) {
              novasSalvas++;
            } else {
              duplicadasEncontradas++;
              if (mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Fatura já cadastrada'),
                    content: Text(
                      'Esta fatura já está no histórico.\n'
                      'Cartão: ${resultado.cartao.isEmpty ? "não identificado" : resultado.cartao}\n'
                      'Vencimento: ${resultado.vencimento}\n'
                      'Valor: ${dinheiro(resultado.totalFatura ?? 0)}\n\n'
                      'Nenhum lançamento foi duplicado.',
                    ),
                    actions: [TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Entendi'),
                    )],
                  ),
                );
              }
            }
          } catch (erro) {
            falhasSalvamento++;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Fatura conciliada, mas não foi salva: $erro'),
                duration: const Duration(seconds: 8),
              ));
            }
          }
        }
      } catch (e, stack) {
        faturas.add(
          FaturaProcessada(
            arquivo:
                arquivo.name,
            textoLayout:
                '',
            textoLayoutPaginas:
                '',
            textoGeometrico:
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
          '$falhas falha(s).\n'
          '$novasSalvas salva(s), $duplicadasEncontradas duplicada(s), '
          '$falhasSalvamento erro(s) ao salvar.';
    });
  }

  Future<void> abrirHistorico() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const TelaHistorico(),
    ));
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
      'Parser: v28 - blocos estruturais de layout + todos os parsers',
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
        f.textoGeometrico,
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
      'Soma compras: ${(ParserItau.centavos(r.somaCompras)/100).toStringAsFixed(2)}',
    );

    b.writeln(
      'Diferença cartão: ${(ParserItau.centavos(r.diferencaCartao ?? 0.0)/100).toStringAsFixed(2)}',
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
      'Soma geral: ${(ParserItau.centavos(r.soma)/100).toStringAsFixed(2)}',
    );

    b.writeln(
      'Diferença geral (lista exportável): ${(ParserItau.centavos(r.diferenca ?? 0.0)/100).toStringAsFixed(2)}',
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
        'Parser: v28-dump Syncfusion',
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

  Future<void> gerarDumpSyncfusionTotal() async {
    if (faturas.isEmpty) return;

    setState(() {
      gerandoDiagnostico = true;
      status = 'Gerando dump Syncfusion...';
    });

    try {
      final b = StringBuffer();
      b.writeln('============================================================');
      b.writeln('DUMP SYNCFUSION TOTAL - CONFERIDOR DE FATURAS ITAU');
      b.writeln('Formato geometrico G: pagina | linha | X | Y | largura | altura | fonte | texto');
      b.writeln('Gerado a partir da mesma extracao PdfTextExtractor usada pelos parsers.');
      b.writeln('Faturas: ${faturas.length}');
      b.writeln('============================================================');

      for (var i = 0; i < faturas.length; i++) {
        final f = faturas[i];
        b.writeln();
        b.writeln('############################################################');
        b.writeln('# FATURA ${i + 1} DE ${faturas.length}');
        b.writeln('# ARQUIVO: ${f.arquivo}');
        b.writeln('############################################################');
        b.writeln();
        b.writeln('===== TEXTO BRUTO SYNCFUSION =====');
        b.writeln(f.textoBruto);
        b.writeln();
        b.writeln('===== TEXTO LAYOUT SYNCFUSION =====');
        b.writeln(f.textoLayout);
        b.writeln();
        b.writeln('===== TEXTO LAYOUT POR PAGINA =====');
        b.writeln(f.textoLayoutPaginas);
        b.writeln();
        b.writeln('===== PALAVRAS / COORDENADAS SYNCFUSION =====');
        b.writeln('COLUNAS: tipo(G) | pagina | indice_linha | X | Y | largura | altura | fonte | texto');
        b.writeln(f.textoGeometrico);
      }

      final pasta = await getTemporaryDirectory();
      final agora = DateTime.now();
      final nome = 'dump_syncfusion_total_'
          '${agora.year}'
          '${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_'
          '${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}'
          '${agora.second.toString().padLeft(2, '0')}.txt';
      final arq = File('${pasta.path}/$nome');
      await arq.writeAsString(b.toString());

      if (mounted) {
        setState(() {
          status = 'Dump Syncfusion gerado. Compartilhe o TXT e envie no chat.';
        });
      }

      await Share.shareXFiles(
        [XFile(arq.path, mimeType: 'text/plain')],
        subject: 'Dump Syncfusion - Conferidor de Faturas',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'Erro ao gerar dump Syncfusion: $e';
        });
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          gerandoDiagnostico = false;
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

          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: processando ? null : abrirHistorico,
            icon: const Icon(Icons.history),
            label: const Text('Histórico de faturas salvas'),
          ),

          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: processando ? null : () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TelaDashboard()),
            ),
            icon: const Icon(Icons.stacked_bar_chart),
            label: const Text('Dashboard de despesas'),
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
                  gerandoDiagnostico || faturas.isEmpty
                      ? null
                      : gerarDumpSyncfusionTotal,
              icon:
                  const Icon(
                Icons.data_object,
              ),
              label:
                  Text(
                gerandoDiagnostico
                    ? 'Gerando arquivo...'
                    : 'Compartilhar dump Syncfusion',
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


class TelaHistorico extends StatefulWidget {
  const TelaHistorico({super.key});
  @override
  State<TelaHistorico> createState() => _TelaHistoricoState();
}

class _TelaHistoricoState extends State<TelaHistorico> {
  late Future<List<Map<String, dynamic>>> dados;
  @override
  void initState() {
    super.initState();
    atualizar();
  }

  void atualizar() { dados = HistoricoLocal.listar(); }

  String reais(int centavos) {
    final valor = (centavos.abs() / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '${centavos < 0 ? '-' : ''}R\$ $valor';
  }

  Future<void> excluir(Map<String, dynamic> f) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir fatura?'),
        content: const Text('Os lançamentos desta fatura serão removidos do histórico local.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await HistoricoLocal.excluir(f['id'] as String);
      if (mounted) setState(atualizar);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e')));
    }
  }

  bool exportandoHistorico = false;

  // Projeta somente parcelas ainda não observadas em faturas reais.
  // O vencimento da fatura determina a competência, não a data da compra.
  Future<void> gerarExcelHistorico() async {
    if (exportandoHistorico) return;
    setState(() => exportandoHistorico = true);
    try {
      final faturas = await HistoricoLocal.listar();
      if (faturas.isEmpty) throw StateError('Nenhuma fatura no histórico.');
      final excel = Excel.createExcel();
      final sheet = excel['Lançamentos'];
      sheet.appendRow([
        for (final t in [
          'Competência', 'Vencimento da fatura', 'Cartão', 'Arquivo de origem',
          'Data da compra', 'Descrição', 'Categoria', 'Valor (R\$)',
          'Parcela atual', 'Total de parcelas', 'Situação', 'Parser',
        ]) TextCellValue(t),
      ]);

      String competencia(String vencimento) {
        final m = RegExp(r'^\d{2}/(\d{2})/(\d{4})$').firstMatch(vencimento.trim());
        if (m == null) return '';
        final mes = int.parse(m.group(1)!);
        if (mes < 1 || mes > 12) return '';
        return '${m.group(2)}-${mes.toString().padLeft(2, '0')}';
      }

      String proximaCompetencia(String base, int meses) {
        final p = base.split('-');
        final data = DateTime(int.parse(p[0]), int.parse(p[1]) + meses, 1);
        return '${data.year}-${data.month.toString().padLeft(2, '0')}';
      }

      String chaveCompra(String cartao, String descricao, int? parcela, int? total, int centavos, String mes) =>
          [cartao.trim(), ParserItau.chave(descricao), parcela ?? 0, total ?? 0, centavos, mes].join('|');

      // Inventário de compras reais: uma parcela efetivamente importada
      // prevalece sobre qualquer projeção da mesma compra.
      final reaisEncontrados = <String>{};
      final itens = <Map<String, dynamic>>[];
      for (final f in faturas) {
        final venc = '${f['vencimento'] ?? ''}';
        final mes = competencia(venc);
        final cartao = '${f['cartao'] ?? ''}';
        for (final raw in (f['compras'] as List? ?? const [])) {
          final e = Map<String, dynamic>.from(raw as Map);
          final centavos = (e['valorCentavos'] as num?)?.toInt() ?? 0;
          final atual = (e['parcelaAtual'] as num?)?.toInt();
          final total = (e['totalParcelas'] as num?)?.toInt();
          final desc = '${e['descricao'] ?? ''}';
          final item = <String, dynamic>{
            'mes': mes, 'vencimento': venc, 'cartao': cartao,
            'arquivo': '${f['arquivo'] ?? ''}', 'data': '${e['data'] ?? ''}',
            'descricao': desc, 'categoria': '${e['categoria'] ?? ''}',
            'centavos': centavos, 'atual': atual, 'total': total,
            'situacao': 'Realizada', 'parser': '${f['estrategia'] ?? ''}',
          };
          itens.add(item);
          reaisEncontrados.add(chaveCompra(cartao, desc, atual, total, centavos, mes));
        }
      }

      // Se a mesma compra aparece em várias faturas, prioriza a parcela
      // mais avançada. Isso impede criar previsões repetidas.
      final grupos = <String, Map<String, dynamic>>{};
      for (final item in itens) {
        final atual = item['atual'] as int?;
        final total = item['total'] as int?;
        final mes = item['mes'] as String;
        if (atual == null || total == null || atual < 1 || total <= atual ||
            total > 60 || mes.isEmpty) continue;
        final grupo = [item['cartao'], ParserItau.chave(item['descricao'] as String),
          total, item['centavos']].join('|');
        final anterior = grupos[grupo];
        if (anterior == null || (atual > (anterior['atual'] as int)) ||
            (atual == anterior['atual'] && mes.compareTo(anterior['mes'] as String) > 0)) {
          grupos[grupo] = item;
        }
      }
      final previstas = <String>{};
      for (final item in grupos.values) {
        final atual = item['atual'] as int;
        final total = item['total'] as int;
        for (var parcela = atual + 1; parcela <= total; parcela++) {
          final mes = proximaCompetencia(item['mes'] as String, parcela - atual);
          final chave = chaveCompra(item['cartao'] as String, item['descricao'] as String,
              parcela, total, item['centavos'] as int, mes);
          if (reaisEncontrados.contains(chave) || !previstas.add(chave)) continue;
          itens.add({...item, 'mes': mes, 'vencimento': '', 'arquivo': '',
            'data': '', 'atual': parcela, 'situacao': 'Projetada'});
        }
      }

      itens.sort((a, b) {
        final porMes = (a['mes'] as String).compareTo(b['mes'] as String);
        if (porMes != 0) return porMes;
        final porCartao = (a['cartao'] as String).compareTo(b['cartao'] as String);
        if (porCartao != 0) return porCartao;
        return (a['descricao'] as String).compareTo(b['descricao'] as String);
      });
      for (final item in itens) {
        sheet.appendRow([
          TextCellValue(item['mes'] as String),
          TextCellValue(item['vencimento'] as String),
          TextCellValue(item['cartao'] as String),
          TextCellValue(item['arquivo'] as String),
          TextCellValue(item['data'] as String),
          TextCellValue(item['descricao'] as String),
          TextCellValue(item['categoria'] as String),
          DoubleCellValue((item['centavos'] as int) / 100),
          if (item['atual'] == null) TextCellValue('') else IntCellValue(item['atual'] as int),
          if (item['total'] == null) TextCellValue('') else IntCellValue(item['total'] as int),
          TextCellValue(item['situacao'] as String),
          TextCellValue(item['parser'] as String),
        ]);
      }
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
      final bytes = excel.encode();
      if (bytes == null) throw StateError('Não foi possível gerar a planilha.');
      final pasta = await getTemporaryDirectory();
      final arquivo = File('${pasta.path}/Historico_Faturas_Parcelas_Futuras.xlsx');
      await arquivo.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(arquivo.path,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar histórico: $e')));
    } finally {
      if (mounted) setState(() => exportandoHistorico = false);
    }
  }

  void detalhes(Map<String, dynamic> f) {
    final compras = (f['compras'] as List? ?? []);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Lançamentos salvos')),
        body: ListView(
          children: [
            ListTile(title: Text('${f['arquivo']}'),
              subtitle: Text('Cartão: ${f['cartao']}  •  Vencimento: ${f['vencimento']}')),
            ...compras.map((item) {
              final e = Map<String, dynamic>.from(item as Map);
              return ListTile(
                title: Text('${e['descricao']}'),
                subtitle: Text('${e['data']} • ${e['categoria']} • '
                  '${e['parcelaAtual'] == null ? 'À vista' : '${e['parcelaAtual']}/${e['totalParcelas']}'}'),
                trailing: Text(reais((e['valorCentavos'] as num).toInt())),
              );
            }),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Histórico de faturas')),
    bottomNavigationBar: SafeArea(child: Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton.icon(
        onPressed: exportandoHistorico ? null : gerarExcelHistorico,
        icon: const Icon(Icons.table_chart),
        label: Text(exportandoHistorico ? 'Gerando Excel...' : 'Gerar Excel do histórico + parcelas futuras'),
      ),
    )),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: dados,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao ler histórico: ${snapshot.error}'));
        }
        final lista = snapshot.data ?? [];
        if (lista.isEmpty) {
          return const Center(child: Text('Nenhuma fatura salva ainda.'));
        }
        final ordenadas = [...lista]..sort((a, b) =>
          (b['salvoEm'] as String).compareTo(a['salvoEm'] as String));
        return ListView.builder(
          itemCount: ordenadas.length,
          itemBuilder: (ctx, i) {
            final f = ordenadas[i];
            return Card(child: ListTile(
              title: Text('${f['arquivo']}'),
              subtitle: Text('Vencimento: ${f['vencimento']}\n'
                'Cartão: ${f['cartao']} • ${f['status']}\n'
                '${(f['compras'] as List? ?? []).length} compras'),
              isThreeLine: true,
              trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(reais((f['totalCentavos'] as num).toInt())),
                IconButton(icon: const Icon(Icons.delete_outline),
                  tooltip: 'Excluir fatura', onPressed: () => excluir(f)),
              ]),
              onTap: () => detalhes(f),
            ));
          },
        );
      },
    ),
  );
}
