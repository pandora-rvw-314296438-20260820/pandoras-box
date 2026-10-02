import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data/eurofish_workspace_api.dart';
import 'enterprise_workspace_home.dart';
import 'plp_resort_workspace.dart';

class SharedEnterpriseWorkspaceScreen extends StatelessWidget {
  const SharedEnterpriseWorkspaceScreen({super.key,required this.selection,required this.onHome,required this.onOpenSection});
  final EnterpriseWorkspaceSelection selection; final VoidCallback onHome; final ValueChanged<String> onOpenSection;
  @override Widget build(BuildContext context)=>switch(selection.workspace.key){
    'plp-boracay'=>_Plp(selection:selection,onHome:onHome,onOpenSection:onOpenSection),
    '1064-euro-fish-traders'=>_Eurofish(selection:selection,onHome:onHome,onOpenSection:onOpenSection),
    'bok'=>_Section(selection:selection,onHome:onHome,onOpenSection:onOpenSection,message:'No verified BOK operating source is connected for this section yet.'),
    _=>_Failure(selection:selection,onHome:onHome,message:'This workspace section is unavailable.'),
  };
}
class _Plp extends StatefulWidget{const _Plp({required this.selection,required this.onHome,required this.onOpenSection});final EnterpriseWorkspaceSelection selection;final VoidCallback onHome;final ValueChanged<String> onOpenSection;@override State<_Plp> createState()=>_PlpState();}
class _PlpState extends State<_Plp>{
 late Future<Map<String,Object?>> future=_load();
 Map<String,Object?> _map(Object? v)=>v is Map<String,Object?>?Map<String,Object?>.from(v):v is Map?v.map((k,x)=>MapEntry(k.toString(),x)):throw StateError('invalid PLP bootstrap');
 Future<Map<String,Object?>> _load() async{final c=Supabase.instance.client;final b=_map(await c.rpc('plp_enterprise_mobile_bootstrap_v1'));try{b['resortCommandCenter']=_map(await c.rpc('plp_resort_command_center_v1'));}catch(_){}return b;}
 String get section=>switch(widget.selection.section.routeSlug){'operations'||'needs-you'=>'operations','guests'=>'guests','sales-revenue'=>'revenue','team-access'=>'team','activity'=>'activity',_=>'today'};
 @override Widget build(BuildContext context)=>FutureBuilder<Map<String,Object?>>(future:future,builder:(context,x){
  if(x.connectionState!=ConnectionState.done)return const _Loading('Loading verified resort data…');
  if(x.hasError||x.data==null)return _Failure(selection:widget.selection,onHome:widget.onHome,message:'Verified resort data is unavailable. Pandora will not invent operational state.',onRetry:()=>setState(()=>future=_load()));
  return PlpResortWorkspaceScreen(key:ValueKey('shared-plp-${widget.selection.section.routeSlug}'),section:plpResortSectionById(section)!,bootstrap:x.data!,onOpenNavigation:(){},onRefresh:()=>setState(()=>future=_load()),onOpenSection:widget.onOpenSection,onOpenActivity:()=>widget.onOpenSection('activity'));
 }));}
class _Eurofish extends StatefulWidget{const _Eurofish({required this.selection,required this.onHome,required this.onOpenSection});final EnterpriseWorkspaceSelection selection;final VoidCallback onHome;final ValueChanged<String> onOpenSection;@override State<_Eurofish> createState()=>_EurofishState();}
class _EurofishState extends State<_Eurofish>{final api=EurofishWorkspaceApi();late Future<EurofishWorkspaceSnapshot> future=api.loadOverview();@override Widget build(BuildContext context)=>FutureBuilder<EurofishWorkspaceSnapshot>(future:future,builder:(context,x){
 if(x.connectionState!=ConnectionState.done)return const _Loading('Loading import/export state…');
 if(x.hasError||x.data==null)return _Failure(selection:widget.selection,onHome:widget.onHome,message:'No authorized import/export provider snapshot is available.',onRetry:()=>setState(()=>future=api.loadOverview()));
 final d=x.data!;return _Section(selection:widget.selection,onHome:widget.onHome,onOpenSection:widget.onOpenSection,metrics:{'Verified evidence':d.verifiedEvidenceCount.toString(),'Needs verification':d.needsVerificationCount.toString(),'Connected sources':d.connectedSourceCount.toString()});
}));}
class _Section extends StatelessWidget{const _Section({required this.selection,required this.onHome,required this.onOpenSection,this.metrics=const{},this.message});final EnterpriseWorkspaceSelection selection;final VoidCallback onHome;final ValueChanged<String> onOpenSection;final Map<String,String> metrics;final String? message;
 @override Widget build(BuildContext context)=>Material(color:const Color(0xFF07111B),child:SafeArea(bottom:false,child:ListView(key:ValueKey('shared-${selection.workspace.key}-${selection.section.routeSlug}'),padding:const EdgeInsets.fromLTRB(18,12,18,120),children:[
 Row(children:[IconButton(key:const ValueKey('shared-workspace-home'),onPressed:onHome,icon:const Icon(Icons.arrow_back_rounded)),Expanded(child:Text(selection.workspace.name,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)))]),const SizedBox(height:28),Text(selection.section.label,style:const TextStyle(color:Colors.white,fontSize:28,fontWeight:FontWeight.w800)),const SizedBox(height:18),
 if(metrics.isNotEmpty)Wrap(spacing:10,runSpacing:10,children:[for(final e in metrics.entries)Container(width:150,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF0C1728),borderRadius:BorderRadius.circular(16),border:Border.all(color:const Color(0xFF263750))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(e.value,style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w800)),Text(e.key,style:const TextStyle(color:Color(0xFF9FB0C5)))]]))]) else Container(key:const ValueKey('shared-workspace-source-unavailable'),padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFF0C1728),borderRadius:BorderRadius.circular(16)),child:Text(message!,style:const TextStyle(color:Colors.white))),
 const SizedBox(height:28),for(final section in selection.workspace.sections)if(section.routeSlug!=selection.section.routeSlug)ListTile(key:ValueKey('shared-section-${selection.workspace.key}-${section.routeSlug}'),leading:Icon(section.icon,color:selection.workspace.accent),title:Text(section.label,style:const TextStyle(color:Colors.white)),onTap:()=>onOpenSection(section.routeSlug))
 ])));}
class _Loading extends StatelessWidget{const _Loading(this.label);final String label;@override Widget build(BuildContext context)=>Material(color:const Color(0xFF07111B),child:Center(child:Semantics(label:label,child:const CircularProgressIndicator())));}
class _Failure extends StatelessWidget{const _Failure({required this.selection,required this.onHome,required this.message,this.onRetry});final EnterpriseWorkspaceSelection selection;final VoidCallback onHome;final String message;final VoidCallback? onRetry;@override Widget build(BuildContext context)=>Material(color:const Color(0xFF07111B),child:SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[IconButton(onPressed:onHome,icon:const Icon(Icons.arrow_back_rounded)),const SizedBox(height:24),Text(selection.workspace.name,style:const TextStyle(color:Color(0xFF9FB0C5))),Text(selection.section.label,style:const TextStyle(color:Colors.white,fontSize:28,fontWeight:FontWeight.w800)),const SizedBox(height:16),Text(message,style:const TextStyle(color:Colors.white)),if(onRetry!=null)...[const SizedBox(height:18),OutlinedButton.icon(key:const ValueKey('shared-workspace-retry'),onPressed:onRetry,icon:const Icon(Icons.refresh_rounded),label:const Text('Retry'))]])))));}
