enum ChannelType {
  backgroundMethod,
  method,
  event,
}

extension ChannelKeyTypeEx on ChannelType {
  String get name {
    switch (this) {
      case ChannelType.backgroundMethod:
        return 'flutter_ios_voip_kit/background';
      case ChannelType.method:
        return 'flutter_ios_voip_kit';
      case ChannelType.event:
        return 'flutter_ios_voip_kit/event';
    }
  }
}
