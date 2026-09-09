# #16 Media Foundation Sink Writer: H.264 аппаратным MFT, mp4 с faststart

**Статус:** done  
**Уровень:** L2  
**Эпик:** #4 Кодирование и контейнер: H.264, AAC, нормальный mp4  
**Этап:** Этап 1. Запись в mp4  
**Компонент:** encoder  
**Trac:** http://127.0.0.1:8000/zigrecstudio-trac/ticket/16

## Что сделать

- `IMFSinkWriter`, `MFVideoFormat_H264`, `MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS`, `MF_SINK_WRITER_DISABLE_THROTTLING`;
- подача кадров из DXGI без копирования в CPU через `IMFDXGIDeviceManager`, запасной путь через буфер;
- moov в начале файла, корректные таймстампы, переменная длительность кадра при пропусках;
- приёмка: файл открывается в Chrome, Windows Media Player, VLC и PowerPoint, `ffprobe` без ошибок.

## Критерий готовности

- [ ] проверка автоматическая: `tools/check.cmd` зелёный, тест на это поведение есть
- [ ] версия бампнута на L2 (`+0.0.1.0`) в том же коммите
- [ ] тикет закрыт комментарием: что сделано и чем проверено
