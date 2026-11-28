import 'package:flutter/material.dart';
import 'package:menval/app/controls.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/calendar/time_zone.dart';
import 'package:menval/features/calendar/calendar_event.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';

/// Inline capture keeps the timetable visible and retains input after failure.
class CalendarEventComposer extends StatefulWidget {
  const CalendarEventComposer({super.key, required this.controller,
    required this.day, required this.weekStart, required this.onSaved,
    required this.onCancel, required this.onDeleted, this.existing});
  final CalendarEventsController controller;
  final DateTime day, weekStart;
  final CalendarEvent? existing;
  final VoidCallback onSaved, onCancel;
  final ValueChanged<CalendarEvent> onDeleted;
  @override
  State<CalendarEventComposer> createState() => _CalendarEventComposerState();
}

class _CalendarEventComposerState extends State<CalendarEventComposer> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _start = TextEditingController(text: _clock(widget.existing?.localStart, '09:00'));
  late final _end = TextEditingController(text: _clock(widget.existing?.localEnd, '10:00'));
  late DateTime _day = dayOf(widget.existing?.localStart ?? widget.day);
  late final int _endDayOffset = widget.existing == null ? 0 :
      daysBetween(widget.existing!.localStart, widget.existing!.localEnd);
  final _attempt = CalendarEventCreateAttempt();
  final _titleFocus = FocusNode();
  String? _validation;
  static String _clock(DateTime? t, String fallback) => t == null ? fallback :
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _titleFocus.requestFocus();
  }); }
  @override
  void dispose() { _title.dispose(); _start.dispose(); _end.dispose(); _titleFocus.dispose(); super.dispose(); }

  int? _minute(String value) {
    final normalized = value.trim().replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
      final c=m[0]!.codeUnitAt(0);return '${c >= 0x6f0 ? c-0x6f0 : c-0x660}';
    });
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalized);
    if (match == null) return null;
    final h=int.parse(match[1]!),m=int.parse(match[2]!);
    return h < 24 && m < 60 ? h*60+m : null;
  }

  Future<void> _save() async {
    if (widget.controller.saving) return;
    final start = _minute(_start.text), end = _minute(_end.text);
    if (_title.text.trim().isEmpty || start == null || end == null ||
        (_endDayOffset == 0 && end <= start)) {
      setState(() => _validation = _title.text.trim().isEmpty
        ? 'عنوان رویداد را بنویسید.' : 'زمان را به صورت ۰۹:۳۰ وارد کنید؛ پایان باید بعد از شروع باشد.');
      return;
    }
    final begin=DateTime(_day.year,_day.month,_day.day,start~/60,start%60);
    final finish=DateTime(_day.year,_day.month,_day.day+_endDayOffset,end~/60,end%60);
    // Reject a normalized DST gap rather than silently moving the appointment.
    if (begin.hour != start~/60 || begin.minute != start%60 || finish.hour != end~/60 || finish.minute != end%60) {
      setState(() => _validation='این ساعت در منطقهٔ زمانی دستگاه وجود ندارد. ساعت دیگری انتخاب کنید.'); return;
    }
    setState(() => _validation=null);
    final zone=widget.existing?.timeZone ?? await deviceTimeZone();
    if (!mounted) return;
    final saved=await widget.controller.save(CalendarEventDraft(title:_title.text,
      start:begin,end:finish,timeZone:zone),existing:widget.existing,attempt:_attempt);
    if (mounted && saved != null) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder:(context,_) {
      final busy=widget.controller.saving, settings=CalendarScope.of(context);
      final days=[for(var i=0;i<7;i++)DateTime(widget.weekStart.year,widget.weekStart.month,widget.weekStart.day+i)];
      if (!days.contains(_day)) days.add(_day);
      final error=_validation ?? widget.controller.error;
      return SoftWell(
        radius:16,padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[Expanded(child:TextField(
            key:const ValueKey('event-title'),controller:_title,focusNode:_titleFocus,
            maxLength:200,enabled:!busy,textInputAction:TextInputAction.done,
            decoration:InputDecoration(labelText:widget.existing==null?'رویداد جدید':'ویرایش رویداد',counterText:''),
            onSubmitted:(_)=>_save(),
          )),const SizedBox(width:8),
          MenvalIconButton(tooltip:'ذخیرهٔ رویداد',icon:Icons.check_rounded,primary:true,onPressed:busy?null:_save),
          MenvalIconButton(tooltip:'بستن فرم رویداد',icon:Icons.close_rounded,onPressed:busy?null:widget.onCancel),
          ]),const SizedBox(height:10),
          Wrap(spacing:12,runSpacing:10,crossAxisAlignment:WrapCrossAlignment.center,children:[
            SizedBox(width:210,child:DropdownButtonFormField<DateTime>(
              key:const ValueKey('event-day'),initialValue:_day,isExpanded:true,
              decoration:const InputDecoration(labelText:'روز'),
              items:[for(final d in days)DropdownMenuItem(value:d,child:Text(formatDate(d,settings,withWeekday:true),maxLines:1,overflow:TextOverflow.ellipsis))],
              onChanged:busy?null:(day){if(day!=null)setState(()=>_day=day);},
            )),
            SizedBox(width:100,child:TextField(key:const ValueKey('event-start'),controller:_start,enabled:!busy,
              keyboardType:TextInputType.datetime,textDirection:TextDirection.ltr,
              decoration:const InputDecoration(labelText:'شروع',hintText:'09:00'))),
            SizedBox(width:100,child:TextField(key:const ValueKey('event-end'),controller:_end,enabled:!busy,
              keyboardType:TextInputType.datetime,textDirection:TextDirection.ltr,
              decoration:const InputDecoration(labelText:'پایان',hintText:'10:00'))),
            if(widget.existing!=null)MenvalIconButton(tooltip:'حذف رویداد',icon:Icons.delete_outline_rounded,
              onPressed:busy?null:()async{final event=widget.existing!;if(await widget.controller.setDeleted(event,true)&&mounted)widget.onDeleted(event);}),
          ]),
          if(_endDayOffset>0)Padding(padding:const EdgeInsets.only(top:8),child:Text('پایان: ${formatDate(DateTime(_day.year,_day.month,_day.day+_endDayOffset),settings)}')),
          if(busy)const Padding(padding:EdgeInsets.only(top:8),child:LinearProgressIndicator()),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:8),child:Semantics(liveRegion:true,child:Text(error,style:TextStyle(color:Theme.of(context).colorScheme.error)))),
        ]),
      );
    },
  );
}
