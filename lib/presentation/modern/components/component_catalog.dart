import 'package:flutter/widgets.dart';
import 'upstream/pages/accordion.dart';
import 'upstream/pages/alert.dart';
import 'upstream/pages/avatar.dart';
import 'upstream/pages/badge.dart';
import 'upstream/pages/breadcrumb.dart';
import 'upstream/pages/button.dart';
import 'upstream/pages/calendar.dart';
import 'upstream/pages/card.dart';
import 'upstream/pages/checkbox.dart';
import 'upstream/pages/checkbox_form_field.dart';
import 'upstream/pages/context_menu.dart';
import 'upstream/pages/date_picker.dart';
import 'upstream/pages/date_picker_form_field.dart';
import 'upstream/pages/dialog.dart';
import 'upstream/pages/keyboard_toolbar.dart';
import 'upstream/pages/separator.dart';
import 'upstream/pages/icon_button.dart';
import 'upstream/pages/input.dart';
import 'upstream/pages/input_form_field.dart';
import 'upstream/pages/input_otp.dart';
import 'upstream/pages/input_otp_form_field.dart';
import 'upstream/pages/menubar.dart';
import 'upstream/pages/popover.dart';
import 'upstream/pages/progress.dart';
import 'upstream/pages/radio_group.dart';
import 'upstream/pages/radio_group_form_field.dart';
import 'upstream/pages/resizable.dart';
import 'upstream/pages/select.dart';
import 'upstream/pages/select_form_field.dart';
import 'upstream/pages/sheet.dart';
import 'upstream/pages/slider.dart';
import 'upstream/pages/sonner.dart';
import 'upstream/pages/switch.dart';
import 'upstream/pages/switch_form_field.dart';
import 'upstream/pages/table.dart';
import 'upstream/pages/tabs.dart';
import 'upstream/pages/portal.dart';
import 'upstream/pages/textarea.dart';
import 'upstream/pages/textarea_form_field.dart';
import 'upstream/pages/time_picker.dart';
import 'upstream/pages/time_picker_form_field.dart';
import 'upstream/pages/toast.dart';
import 'upstream/pages/tooltip.dart';
import 'upstream/pages/typography.dart';

final shadcnDemoRoutes = <String, WidgetBuilder>{
  '/accordion': (_) => const AccordionPage(),
  '/alert': (_) => const AlertPage(),
  '/avatar': (_) => const AvatarPage(),
  '/badge': (_) => const BadgePage(),
  '/breadcrumb': (_) => const BreadcrumbPage(),
  '/button': (_) => const ButtonPage(),
  '/calendar': (_) => const CalendarPage(),
  '/card': (_) => const CardPage(),
  '/checkbox': (_) => const CheckboxPage(),
  '/checkbox-form-field': (_) => const CheckboxFormFieldPage(),
  '/context-menu': (_) => const ContextMenuPage(),
  '/date-picker': (_) => const DatePickerPage(),
  '/date-picker-form-field': (_) => const DatePickerFormFieldPage(),
  '/dialog': (_) => const DialogPage(),
  '/divider': (_) => const SeparatorPage(),
  '/icon-button': (_) => const IconButtonPage(),
  '/input': (_) => const InputPage(),
  '/input-OTP': (_) => const InputOTPPage(),
  '/input-OTP-form-field': (_) => const InputOTPFormFieldPage(),
  '/input-form-field': (_) => const InputFormFieldPage(),
  '/keyboard-toolbar': (_) => const KeyboardToolbarPage(),
  '/menubar': (_) => const MenubarPage(),
  '/popover': (_) => const PopoverPage(),
  '/portal': (_) => const ShadPortalPage(),
  '/progress': (_) => const ProgressPage(),
  '/radio-group': (_) => const RadioPage(),
  '/radio-group-form-field': (_) => const RadioGroupFormFieldPage(),
  '/resizable': (_) => const ResizablePage(),
  '/select': (_) => const SelectPage(),
  '/select-form-field': (_) => const SelectFormFieldPage(),
  '/sheet': (_) => const SheetPage(),
  '/slider': (_) => const SliderPage(),
  '/sonner': (_) => const SonnerPage(),
  '/switch': (_) => const SwitchPage(),
  '/switch-form-field': (_) => const SwitchFormFieldPage(),
  '/table': (_) => const TablePage(),
  '/tabs': (_) => const TabsPage(),
  '/textarea': (_) => const TextareaPage(),
  '/textarea-form-field': (_) => const TextareaFormFieldPage(),
  '/time-picker': (_) => const TimePickerPage(),
  '/time-picker-form-field': (_) => const TimePickerFormFieldPage(),
  '/toast': (_) => const ToastPage(),
  '/tooltip': (_) => const TooltipPage(),
  '/typography': (_) => const TypographyPage(),
};
