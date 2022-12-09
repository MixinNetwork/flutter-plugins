import 'package:xml/xml.dart';

enum ToastDuration {
  short,
  long,
}

enum ToastScenario {
  /// A reminder notification. This will be displayed pre-expanded and stay on
  /// the user's screen till dismissed.
  reminder,

  /// An alarm notification. This will be displayed pre-expanded and stay on the
  /// user's screen till dismissed. Audio will loop by default and will use alarm audio.
  alarm,

  /// An incoming call notification. This will be displayed pre-expanded in a
  /// special call format and stay on the user's screen till dismissed.
  /// Audio will loop by default and will use ringtone audio.
  incomingCall,

  /// An important notification. This allows users to have more control over
  /// what apps can send them high-priority toast notifications that can break
  /// through Focus Assist (Do not Disturb).
  /// This can be modified in the notifications settings.
  urgent,
}

abstract class ToastChild {
  XmlElement get _element;
}

class Toast {
  final XmlElement _toast = XmlElement(XmlName('toast'));

  Toast({
    /// A string that is passed to the application when it is activated by the toast.
    /// The format and contents of this string are defined by the app for its own use.
    /// When the user taps or clicks the toast to launch its associated app,
    /// the launch string provides the context to the app that allows it to show
    /// the user a view relevant to the toast content, rather than launching in its default way.
    String? launch,

    /// The amount of time the toast should display.
    ToastDuration? duration,
    DateTime? displayTimestamp,

    /// The scenario your toast is used for, like an alarm or reminder.
    ToastScenario? scenario,

    /// Specifies whether styled buttons should be used.
    /// The styling of the button is determined by the **hint-buttonStyle**
    /// attribute of the [action](element-action.md) element.
    bool? useButtonStyle,
    List<ToastChild> children = const [],
  }) {
    if (launch != null) {
      _toast.attributes.add(XmlAttribute(XmlName('launch'), launch));
    }
    if (duration != null) {
      _toast.attributes.add(XmlAttribute(XmlName('duration'), duration.name));
    }
    if (displayTimestamp != null) {
      _toast.attributes.add(XmlAttribute(
          XmlName('displayTimestamp'), displayTimestamp.toIso8601String()));
    }
    if (scenario != null) {
      _toast.attributes.add(XmlAttribute(XmlName('scenario'), scenario.name));
    }
    if (useButtonStyle != null) {
      _toast.attributes.add(
          XmlAttribute(XmlName('useButtonStyle'), useButtonStyle.toString()));
    }
    _toast.children.addAll(children.map((e) => e._element));
  }

  String toXmlString({bool pretty = false}) {
    return _toast.toXmlString(pretty: pretty);
  }
}

enum ToastAudioSource {
  defaultSound,
  im,
  mail,
  reminder,
  sms,
  alarm,
  alarm2,
  alarm3,
  alarm4,
  alarm5,
  alarm6,
  alarm7,
  alarm8,
  alarm9,
  alarm10,
  call,
  call2,
  call3,
  call4,
  call5,
  call6,
  call7,
  call8,
  call9,
  call10,
}

extension _AudioSourceString on ToastAudioSource {
  String get sourceString {
    switch (this) {
      case ToastAudioSource.defaultSound:
        return 'ms-winsoundevent:Notification.Default';
      case ToastAudioSource.im:
        return 'ms-winsoundevent:Notification.IM';
      case ToastAudioSource.mail:
        return 'ms-winsoundevent:Notification.Mail';
      case ToastAudioSource.reminder:
        return 'ms-winsoundevent:Notification.Reminder';
      case ToastAudioSource.sms:
        return 'ms-winsoundevent:Notification.SMS';
      case ToastAudioSource.alarm:
        return 'ms-winsoundevent:Notification.Looping.Alarm';
      case ToastAudioSource.alarm2:
        return 'ms-winsoundevent:Notification.Looping.Alarm2';
      case ToastAudioSource.alarm3:
        return 'ms-winsoundevent:Notification.Looping.Alarm3';
      case ToastAudioSource.alarm4:
        return 'ms-winsoundevent:Notification.Looping.Alarm4';
      case ToastAudioSource.alarm5:
        return 'ms-winsoundevent:Notification.Looping.Alarm5';
      case ToastAudioSource.alarm6:
        return 'ms-winsoundevent:Notification.Looping.Alarm6';
      case ToastAudioSource.alarm7:
        return 'ms-winsoundevent:Notification.Looping.Alarm7';
      case ToastAudioSource.alarm8:
        return 'ms-winsoundevent:Notification.Looping.Alarm8';
      case ToastAudioSource.alarm9:
        return 'ms-winsoundevent:Notification.Looping.Alarm9';
      case ToastAudioSource.alarm10:
        return 'ms-winsoundevent:Notification.Looping.Alarm10';
      case ToastAudioSource.call:
        return 'ms-winsoundevent:Notification.Looping.Call';
      case ToastAudioSource.call2:
        return 'ms-winsoundevent:Notification.Looping.Call2';
      case ToastAudioSource.call3:
        return 'ms-winsoundevent:Notification.Looping.Call3';
      case ToastAudioSource.call4:
        return 'ms-winsoundevent:Notification.Looping.Call4';
      case ToastAudioSource.call5:
        return 'ms-winsoundevent:Notification.Looping.Call5';
      case ToastAudioSource.call6:
        return 'ms-winsoundevent:Notification.Looping.Call6';
      case ToastAudioSource.call7:
        return 'ms-winsoundevent:Notification.Looping.Call7';
      case ToastAudioSource.call8:
        return 'ms-winsoundevent:Notification.Looping.Call8';
      case ToastAudioSource.call9:
        return 'ms-winsoundevent:Notification.Looping.Call9';
      case ToastAudioSource.call10:
        return 'ms-winsoundevent:Notification.Looping.Call10';
    }
  }
}

class ToastChildAudio extends ToastChild {
  @override
  final XmlElement _element = XmlElement(XmlName('audio'));

  ToastChildAudio({
    /// The media file to play in place of the default sound.
    ToastAudioSource? source,

    /// Set to true if the sound should repeat as long as the toast is shown;
    /// false to play only once. If this attribute is set to true,
    /// the duration attribute in the toast element must also be set.
    /// There are specific sounds provided to be used when looping.
    /// Note that UWP apps support neither looping audio nor long-duration toasts.
    bool? loop,

    /// True to mute the sound; false to allow the toast notification sound to play.
    bool? silent,
  }) {
    if (source != null) {
      _element.attributes
          .add(XmlAttribute(XmlName('src'), source.sourceString));
    }
    if (loop != null) {
      _element.attributes.add(XmlAttribute(XmlName('loop'), loop.toString()));
    }
    if (silent != null) {
      _element.attributes
          .add(XmlAttribute(XmlName('silent'), silent.toString()));
    }
  }
}

enum ToastCommandId {
  snooze,
  dismiss,
  video,
  voice,
  decline,
}

class ToastCommand {
  final XmlElement _command = XmlElement(XmlName('command'));

  ToastCommand({
    /// Specifies one command from the system-defined command list.
    /// These values correspond to available actions that the user can take.
    /// Two scenarios are available through the commands element.
    /// Only certain commands are used with a given scenario, as shown here:
    ///
    /// alarm
    ///   snooze
    ///   dismiss
    ///
    /// incomingCall
    ///   video
    ///   voice
    ///   decline
    ToastCommandId? id,

    /// An argument string that can be passed to the associated app to provide
    /// specifics about the action that it should execute in response to the user action.
    String? arguments,
  }) {
    if (id != null) {
      _command.attributes.add(XmlAttribute(XmlName('id'), id.name));
    }
    if (arguments != null) {
      _command.attributes.add(XmlAttribute(XmlName('arguments'), arguments));
    }
  }
}

enum ToastCommandScenario {
  alarm,
  incomingCall,
}

class ToastChildCommands implements ToastChild {
  final XmlElement _commands = XmlElement(XmlName('commands'));

  ToastChildCommands({
    /// The intended use of the notification.
    ToastCommandScenario? scenario,

    /// Specifies a scenario-associated button shown in a toast.
    List<ToastCommand>? children,
  }) {
    if (scenario != null) {
      _commands.attributes
          .add(XmlAttribute(XmlName('scenario'), scenario.name));
    }
    if (children != null) {
      for (final child in children) {
        _commands.children.add(child._command);
      }
    }
  }

  @override
  XmlElement get _element => _commands;
}

class ToastChildVisual implements ToastChild {
  final XmlElement _visual = XmlElement(XmlName('visual'));

  ToastChildVisual({
    /// The version of the toast XML schema this particular payload was developed for.
    int? version,

    /// The target locale of the XML payload,
    /// specified as BCP-47 language tags such as "en-US" or "fr-FR".
    /// This locale is overridden by any locale specified in binding or text.
    /// If this value is a literal string, this attribute defaults to the user's UI language.
    /// If this value is a string reference, this attribute defaults to the
    /// locale chosen by Windows Runtime in resolving the string.
    String? lang,

    /// A default base URI that is combined with relative URIs in image source attributes.
    String? baseUri,

    /// Set to "true" to allow Windows to append a query string to the image URI
    /// supplied in the toast notification.
    /// Use this attribute if your server hosts images and can handle query strings,
    /// either by retrieving an image variant based on the query strings or
    /// by ignoring the query string and returning the image as specified without
    /// the query string. This query string specifies scale, contrast setting,
    /// and language;
    ///
    /// for instance, a value of
    ///
    /// "www.website.com/images/hello.png"
    ///
    /// given in the notification becomes
    ///
    /// "www.website.com/images/hello.png?ms-scale=100&ms-contrast=standard&ms-lang=en-us"
    bool? addImageQuery,

    /// The binding template to use for the notification.
    /// This attribute is required.
    required ToastVisualBinding binding,
  }) {
    if (version != null) {
      _visual.attributes
          .add(XmlAttribute(XmlName('version'), version.toString()));
    }
    if (lang != null) {
      _visual.attributes.add(XmlAttribute(XmlName('lang'), lang));
    }
    if (baseUri != null) {
      _visual.attributes.add(XmlAttribute(XmlName('baseUri'), baseUri));
    }
    if (addImageQuery != null) {
      _visual.attributes.add(
          XmlAttribute(XmlName('addImageQuery'), addImageQuery.toString()));
    }
    _visual.children.add(binding._binding);
  }

  @override
  XmlElement get _element => _visual;
}

abstract class ToastVisualBindingChild {
  XmlElement get _element;
}

class ToastVisualBinding {
  final XmlElement _binding = XmlElement(XmlName('binding'));

  ToastVisualBinding({
    /// This value must be set to "ToastGeneric"
    String template = 'ToastGeneric',

    /// A template to use if the primary template cannot be found,
    /// for use with backward compatibility.
    String? fallback,

    /// The same as the lang attribute on the visual element.
    String? lang,

    /// The same as the addImageQuery attribute on the visual element.
    bool? addImageQuery,

    /// The same as the baseUri attribute on the visual element.
    String? baseUri,

    /// The child elements of the binding.
    /// This attribute is required.
    required List<ToastVisualBindingChild> children,
  }) {
    _binding.attributes.add(XmlAttribute(XmlName('template'), template));
    if (fallback != null) {
      _binding.attributes.add(XmlAttribute(XmlName('fallback'), fallback));
    }
    if (lang != null) {
      _binding.attributes.add(XmlAttribute(XmlName('lang'), lang));
    }
    if (addImageQuery != null) {
      _binding.attributes.add(
          XmlAttribute(XmlName('addImageQuery'), addImageQuery.toString()));
    }
    if (baseUri != null) {
      _binding.attributes.add(XmlAttribute(XmlName('baseUri'), baseUri));
    }
    for (final child in children) {
      _binding.children.add(child._element);
    }
  }
}

enum ToastImagePlacement {
  appLogoOverride,
  hero,
}

class ToastVisualBindingChildImage implements ToastVisualBindingChild {
  final XmlElement _image = XmlElement(XmlName('image'));

  ToastVisualBindingChildImage({
    /// The URI of the image source, using one of these protocol handlers:
    /// http:// or https:// A web-based image.
    /// ms-appx:/// An image included in the app package.
    /// ms-appdata:///local/ An image saved to local storage.
    /// file:/// A local image. (Supported only for desktop apps. This protocol cannot be used by UWP apps.)
    required String src,

    /// A description of the image, for users of assistive technologies.
    String? alt,

    /// The placement of the image.
    ///
    /// "appLogoOverride" - The image replaces your app's logo in the toast notification.
    /// "hero" - The image is displayed as a hero image.
    /// For more information, see [Toast content](https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/adaptive-interactive-toasts).
    ToastImagePlacement? placement,
    bool? addImageQuery,

    /// The image element in the toast template that this image is intended for.
    /// If a template has only one image, then this value is 1.
    /// The number of available image positions is based on the template definition.
    required int id,

    /// true to crop the image into a circle.
    bool crop = false,
  }) {
    _image.attributes.add(XmlAttribute(XmlName('src'), src));
    if (alt != null) {
      _image.attributes.add(XmlAttribute(XmlName('alt'), alt));
    }
    if (placement != null) {
      _image.attributes.add(XmlAttribute(XmlName('placement'), placement.name));
    }
    if (addImageQuery != null) {
      _image.attributes.add(
          XmlAttribute(XmlName('addImageQuery'), addImageQuery.toString()));
    }
    _image.attributes.add(XmlAttribute(XmlName('id'), id.toString()));
    if (crop) {
      _image.attributes.add(XmlAttribute(XmlName('crop'), 'circle'));
    }
  }

  @override
  XmlElement get _element => _image;
}

class ToastVisualBindingChildText implements ToastVisualBindingChild {
  final XmlElement _text = XmlElement(XmlName('text'));

  ToastVisualBindingChildText({
    required String text,

    /// The text element in the toast template that this text is intended for.
    /// If a template has only one text element, then this value is 1.
    /// The number of available text positions is based on the template definition.
    required int id,

    /// The same as the lang attribute on the visual element.
    String? lang,

    /// The placement of the text. Introduced in Anniversary Update.
    /// If you specify the value "attribution",
    /// the text is always displayed at the bottom of your notification,
    /// along with your app's identity or the notification's timestamp.
    /// On older versions of Windows that don't support attribution text,
    /// the text will simply be displayed as another text element
    /// (assuming you don't already have the maximum of three text elements).
    ///
    /// For more information, see [Toast content](/windows/apps/design/shell/tiles-and-notifications/adaptive-interactive-toasts).
    String? placement,

    /// Set to "true" to center the text for incoming call notifications.
    /// This value is only used for notifications with with a scenario value of "incomingCall";
    /// otherwise, it is ignored. For more information, see Toast content.
    bool? callScenarioCenterAlign,
  }) {
    _text.attributes.add(XmlAttribute(XmlName('id'), id.toString()));
    if (lang != null) {
      _text.attributes.add(XmlAttribute(XmlName('lang'), lang));
    }
    if (placement != null) {
      _text.attributes.add(XmlAttribute(XmlName('placement'), placement));
    }
    if (callScenarioCenterAlign != null) {
      _text.attributes.add(XmlAttribute(XmlName('callScenarioCenterAlign'),
          callScenarioCenterAlign.toString()));
    }
    _text.children.add(XmlText(text));
  }

  @override
  XmlElement get _element => _text;
}

abstract class ToastActionElement {
  XmlElement get _element;
}

class ToastChildActions implements ToastChild {
  final XmlElement _actions = XmlElement(XmlName('actions'));

  ToastChildActions({
    /// Container element for declaring up to five inputs
    /// and up to five button actions for the toast notification.
    required List<ToastActionElement> children,
  }) {
    for (final child in children) {
      _actions.children.add(child._element);
    }
  }

  @override
  XmlElement get _element => _actions;
}

enum ToastInputType {
  text,
  selection,
}

class ToastActionInput implements ToastActionElement {
  final XmlElement _input = XmlElement(XmlName('input'));

  ToastActionInput({
    /// The ID associated with the input.
    required String id,
    required ToastInputType type,

    /// The placeholder displayed for text input.
    String? placeHolderContent,

    /// Text displayed as a label for the input.
    String? title,
    List<ToastActionInputSelection>? selections,
  }) {
    _input.attributes.add(XmlAttribute(XmlName('id'), id));
    _input.attributes.add(XmlAttribute(XmlName('type'), type.name));
    if (placeHolderContent != null) {
      _input.attributes
          .add(XmlAttribute(XmlName('placeHolderContent'), placeHolderContent));
    }
    if (title != null) {
      _input.attributes.add(XmlAttribute(XmlName('title'), title));
    }
    if (selections != null) {
      for (final selection in selections) {
        _input.children.add(selection._selection);
      }
    }
  }

  @override
  XmlElement get _element => _input;
}

class ToastActionInputSelection {
  final XmlElement _selection = XmlElement(XmlName('selection'));

  ToastActionInputSelection({
    /// The ID associated with the selection.
    required String id,

    /// The text displayed for the selection.
    required String content,
  }) {
    _selection.attributes.add(XmlAttribute(XmlName('id'), id));
    _selection.attributes.add(XmlAttribute(XmlName('content'), content));
  }
}

enum ToastActionActivationType {
  foreground,
  background,
  protocol,
}

enum ToastActionHintButtonStyle {
  success,
  critical,
}

class ToastAction implements ToastActionElement {
  final XmlElement _action = XmlElement(XmlName('action'));

  ToastAction({
    /// The content displayed on the button.
    required String content,

    /// App-defined string of arguments that the app will later receive if the user clicks this button.
    required String arguments,

    /// An argument string that can be passed to the associated app to provide
    /// specifics about the action that it should execute in response to the user action.
    String? type,

    /// Decides the type of activation that will be used when the user interacts with a specific action.
    /// "foreground" - Default value. Your foreground app is launched.
    /// "background" - Your corresponding background task is triggered,
    ///                and you can execute code in the background without interrupting the user.
    /// "protocol" - Launch a different app using protocol activation.
    ToastActionActivationType? activationType,

    /// When set to "contextMenu", the action becomes a context menu action
    /// added to the toast notification's context menu rather than a traditional toast button.
    String? placement,

    /// The URI of the image source for a toast button icon. These icons are white transparent 16x16 pixel images at 100% scaling and should have no padding included in the image itself. If you choose to provide icons on a toast notification, you must provide icons for ALL of your buttons in the notification, as it transforms the style of your buttons into icon buttons. Use one of the following protocol handlers:
    /// http:// or https:// - A web-based image.
    /// ms-appx:/// - An image included in the app package.
    /// ms-appdata:///local/ - An image saved to local storage.
    /// file:/// - A local image. (Supported only for desktop apps. This protocol cannot be used by UWP apps.)
    String? imageUri,

    /// Set to the Id of an input to position button beside the input.
    String? hintInputId,

    /// The button style. useButtonStyle must be set to true in the toast element.
    /// "Success" - The button is green
    /// "Critical" - The button is red.
    ToastActionHintButtonStyle? hintButtonStyle,

    /// The tooltip for a button, if the button has an empty content string.
    String? hintToolTip,
  }) {
    _action.attributes.add(XmlAttribute(XmlName('content'), content));
    _action.attributes.add(XmlAttribute(XmlName('arguments'), arguments));
    if (type != null) {
      _action.attributes.add(XmlAttribute(XmlName('type'), type));
    }
    if (activationType != null) {
      _action.attributes.add(XmlAttribute(
          XmlName('activationType'), activationType.name.toLowerCase()));
    }
    if (placement != null) {
      _action.attributes.add(XmlAttribute(XmlName('placement'), placement));
    }
    if (imageUri != null) {
      _action.attributes.add(XmlAttribute(XmlName('imageUri'), imageUri));
    }
    if (hintInputId != null) {
      _action.attributes
          .add(XmlAttribute(XmlName('hint-inputId'), hintInputId));
    }
    if (hintButtonStyle != null) {
      final String style;
      switch (hintButtonStyle) {
        case ToastActionHintButtonStyle.success:
          style = 'Success';
          break;
        case ToastActionHintButtonStyle.critical:
          style = 'Critical';
          break;
      }
      _action.attributes.add(XmlAttribute(XmlName('hint-buttonStyle'), style));
    }
    if (hintToolTip != null) {
      _action.attributes
          .add(XmlAttribute(XmlName('hint-toolTip'), hintToolTip));
    }
  }

  @override
  XmlElement get _element => _action;
}
