# Изучение darling-metal — 2026-11-13

Отдельная чистая копия находится в
`build/metal-baseline/reference/darling-metal` вместе с закреплённым Indium.
Каталог `build/` игнорируется Git; эту копию можно использовать для сравнения,
но её нужно отдельно сохранять, если удаляется весь каталог сборки.

## Что именно скопировано

| Репозиторий | Ревизия |
| --- | --- |
| [darling-metal](https://github.com/darlinghq/darling-metal) | `51bc1937a0cd6472458d084dfe3ba3ca3b4ea3a4` |
| [Indium](https://github.com/darlinghq/indium), его подмодуль | `15e3a7ba071f2ffc4df542a6e7c76783fd350441` |

HEAD свежей копии darling-metal совпал с исходной ревизией нашего
`src/external/metal`. Ревизия Indium также совпала. Следовательно, это уже основа
нашей реализации; новых upstream-коммитов для переноса при этой проверке нет.
Чистая копия не содержит наших изменений компиляции исходников MSL.
Оба скопированных рабочих дерева остались чистыми.

`CMakeLists.txt` рассчитан на интеграцию в сборку Darling: использует её функции
создания SDK/framework. Отдельный clone сам по себе не является самостоятельным
проектом с готовой универсальной командой сборки.

## Устройство и примеры

Путь команд в изученной реализации:

```text
Клиент: публичные Objective-C API Metal / MetalKit
  → darling-metal: объекты, дескрипторы, преобразование аргументов
  → Indium: C++ ресурсы и команды
  → Vulkan: реальные GPU-команды
```

Показ окна дополнительно проходит через MTKView и CAMetalLayer в Darling.
IndiumKit — отдельная вспомогательная библиотека для native-примеров Indium;
она не заменяет реализацию Objective-C MetalKit в приложении Darling.

В upstream есть `examples/triangle`: создание pipeline, передача вершин и размера
окна через `setVertexBytes`, делегат MTKView и показ drawable. Его `build.sh`
вызывает `xcrun metal` и `xcrun metallib`, а renderer использует
`newDefaultLibrary`. Наличие этого примера не означает наличие исходного
компилятора MSL в чистом Darling. Наш необязательный мост через mslc даёт другой
путь: `newLibraryWithSource:options:error:` → SPIR-V и reflection → Indium.

В Indium также есть примеры cube, lighting, texturing, sampler и cubemap.
Они показывают направления развития. Их наличие не считается подтверждением
работы этих сцен через наш Objective-C API и наш мост mslc: в этой работе эти
сцены не запускались, их shader binaries не исследовались.

## Карта возможностей

«Есть путь в коде» ниже означает просмотр делегирования вплоть до backend,
а не полную проверку контракта, ошибок и всех сочетаний состояний.
Пути приведены относительно чистой копии; соответствующие файлы имеются
и в рабочем `src/external/metal`.

| Возможность | Найденная реализация | Что это даёт и что ещё проверить |
| --- | --- | --- |
| Прозрачность, смешивание цветов | `src/Metal/MTLRenderPipeline.mm`: параметры blending передаются в Indium; `deps/indium/src/indium/render-pipeline.cpp`: настраивается Vulkan color blending | Перекрывающиеся полупрозрачные фигуры и плавное исчезновение. В нашей сцене не проверено; нужны явные blend factors и пиксельная проверка результата. |
| Прямоугольная обрезка | `src/Metal/MTLRenderCommandEncoder.mm`: `setScissorRect`; backend вызывает `vkCmdSetScissorWithCount` | Фигуры внутри заданной области. Проверить прямоугольник внутри кадра, границы и смену состояния. |
| Индексная геометрия | Тот же encoder: `drawIndexedPrimitives`; backend вызывает `vkCmdDrawIndexed` | Сетки с общими вершинами. Проверить uint16/uint32 индексы, смещения и сравнение с обычным draw. |
| Несколько экземпляров фигуры одним draw | Перегрузки `drawPrimitives` с `instanceCount`/`baseInstance`; backend передаёт их в `vkCmdDraw` | Кандидат для множества одинаковых фигур или частиц. Сначала отдельно проверить поддержку входов шейдера нашим mslc и адресацию данных экземпляров. |
| Текстуры и семплеры | `MTLTexture.mm`, `MTLSamplerState.mm`, `MTLDevice.mm`, методы `setFragmentTexture`/`setFragmentSamplerState` в encoder | Основа для изображений и спрайтов есть. Наш `MTLSourceLibrary.mm` сейчас принимает только Buffer resources: для source-шейдеров нужно расширить преобразование reflection, затем проверить выборку текстуры. |
| Загрузка изображений | `src/MetalKit/MTKTextureLoader.m`: CGImage, URL, NSData, поиск отдельных ресурсов; далее создаётся и заполняется MTLTexture | Можно изучать путь PNG → ImageIO/CoreGraphics → Metal. Asset catalogs не поддержаны, ModelIO-вход и некоторые опции приводят к отказу, включая abort. Нужны тесты формата, ориентации и alpha. |
| Depth buffer | `MTLDepthStencilDescriptor.mm`, `MTLDevice.mm`, render-pass attachments и depth state в Indium | Кандидат для перекрывающихся 3D-примитивов. Metal-путь есть, но `MTKView.depthStencilTexture` возвращает nil: сначала явная depth texture и render pass либо реализация контракта MTKView. |
| MSAA | Render-pass resolve attachments и `rasterSampleCount` доходят до Indium; имеется тест `test/multisample-resolve` | Сглаживание краёв. Backend отдельно проверен ниже. `MTKView.multisampleColorTexture` возвращает nil, а текущий pass использует drawable напрямую: одного изменения `sampleCount` недостаточно. |
| GPU-копирование и mipmaps | `MTLBlitCommandEncoder.mm` передаёт copy/fill/generateMipmaps в Indium; backend содержит Vulkan copy/fill/blit | Кандидат для загрузки ресурсов и цепочек mipmap. Полный контракт не проверен: есть ограничения blit options и выравнивания fill. Loader пока отказывает в опциях генерации mipmaps, несмотря на наличие blit-пути. |
| Compute на буферах | `MTLComputeCommandEncoder.mm` и Indium compute encoder; наш клиент уже проверяет запись в buffer index 5 | Основа для вычисляемых позиций/цветов. Отдельная задача — передача результата compute в render с корректным порядком и синхронизацией; текущий readback этого ещё не доказывает. |

## Что нельзя считать готовой функциональностью

- `MTLStencilDescriptor` пока перехватывает вызовы заглушкой; слой Metal не
  передаёт stencil descriptors в Indium. Наличие stencil-кода в backend
  не означает готовность публичного stencil API.
- В `src/MPSKernel.m` Gaussian blur не реализован, а
  `MPSSupportsMTLDevice` возвращает NO. Имя MetalPerformanceShaders в описании
  репозитория не означает работающие фильтры.
- В `MTLDrawable.mm` timed presentation и presented handler содержат abort.
  Текущая обычная презентация не проверяет эти API.
- Файлы acceleration structures, indirect command buffer и heap содержат
  в основном описатели/вспомогательные классы. По ним нельзя обещать готовый
  ray tracing, indirect execution или управление heap-ресурсами.
- В backend изменение triangle fill mode на режим, отличный от Fill, бросает
  исключение: wireframe нельзя объявлять работающим по одному наличию setter.
- Часть descriptor-полей и reflection остаётся неполной. Новую возможность
  следует проверять по всему пути, включая преобразование аргументов, backend,
  компилятор шейдера и клиентский результат.

## Дополнительная проверка при изучении

Собран существующий target `indium-test-multisample-resolve` из нашего
неизменённого Indium той же ревизии. Тест сам собирает GLSL-шейдеры через
glslangValidator; не требует Apple-компилятора или исследования Apple binaries.

Команды из корня Darling:

```sh
cmake --build build/metal-baseline/indium --parallel 2 \
  --target indium-test-multisample-resolve
env VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json \
  build/metal-baseline/indium/test/multisample-resolve/indium-test-multisample-resolve
```

Результат наблюдения 2026-11-13:

```text
PASS samples=1 operation=0 mismatched_bytes=0
PASS samples=1 operation=1 mismatched_bytes=0
PASS samples=1 operation=2 mismatched_bytes=0
PASS samples=4 operation=0 mismatched_bytes=0
PASS samples=4 operation=1 mismatched_bytes=0
PASS samples=4 operation=2 mismatched_bytes=0
RESULT failures=0
```

Проверены красная/синяя очистка и draw с 1×/4×; для 4× используется resolve
в single-sample texture с чтением результата. Это native backend-тест на
Mesa lavapipe, а не проверка сглаживания в окне MetalKit или на Intel GPU.

## Предлагаемый порядок следующих работ

1. **Прозрачность и scissor.** Добавить отдельные сцены с известными цветами
   перекрытия и явной областью обрезки; сравнивать readback с независимым
   эталоном. Это опирается на текущие буферы без новых типов shader resources.
2. **MSAA для наших фигур.** Начать с явных multisample/resolve attachments,
   проверить поддержку sample count у device и результат offscreen.
   Автоматические ресурсы MTKView реализовывать отдельно в MetalKit.
3. **Текстурированный прямоугольник.** Расширить source reflection для
   textures/samplers согласно контракту mslc и интерфейсу Indium; проверить
   маленькую процедурную текстуру, затем отдельно ImageIO/MTKTextureLoader.
4. **Индексные meshes и instancing.** Проверить эквивалентность геометрии,
   смещения и несколько экземпляров; производительность измерять отдельно.
5. **Depth и простая 3D-сцена.** Сначала проверка перекрытия двух треугольников
   при разном порядке draw, затем вращающийся куб.
6. **Compute → render.** Вычислять позиции в GPU-буфере и использовать его
   при рисовании; проверить синхронизацию и результат на фиксированном времени.

Это направления для последующих задач. Новая функциональность Metal в ходе
этого изучения не добавлялась.

## Источники и происхождение

Выводы основаны на исходниках открытых darling-metal и Indium указанных ревизий,
их заголовках, примере triangle и описаниях тестов, а также на выполненном
native MSAA-тесте. Для будущей реализации каждую семантику и тесты необходимо
сверять с публичным контрактом Apple/Vulkan, особенно там, где upstream содержит
TODO или предположения о defaults.

Основные файлы darling-metal помечены MPL-2.0; пример triangle содержит
MIT/ISC notices. Текст `deps/indium/LICENSE` соответствует 0BSD
(разрешение без условия сохранения notice), не следует путать его с ISC.
Для повторного использования конкретного файла нужно проверять его notice.
В этой работе внешняя реализация в наш код не переносилась.
CoreCrypto и другие ограниченные исходники Apple не использовались;
дизассемблирование и декомпиляция Apple binaries не выполнялись.
