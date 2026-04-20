import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Снимает фокус и прячет клавиатуру вместе с iOS input accessory.
void dismissKeyboardAndInputChrome() {
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// После смены экрана accessory на iOS иногда остаётся до следующего кадра.
void dismissKeyboardAndInputChromeAfterRouteChange() {
  dismissKeyboardAndInputChrome();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
  });
}
