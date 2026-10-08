import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/pandora_config.dart';
import '../../app/pandora_dependencies.dart';
import '../../core/security/pandora_auth.dart';

class PlpBillingScreen extends StatefulWidget{
 const PlpBillingScreen({super.key,required this.organizationId,required this.onOpenNavigation});
 final String? organizationId; final VoidCallback onOpenNavigation;
 @override State<PlpBillingScreen> createState()=>_PlpBillingScreenState();
}
class _PlpBillingScreenState extends State<PlpBillingScreen>{
 static const ink=Color(0xFF171512),muted=Color(0xFF746F67),canvas=Color(0xFFFAF8F3),accent=Color(0xFF82764F);
 static const plans=[('launch','Launch',49,'1,000 requests / month'),('professional','Professional',149,'5,000 requests / month')];
 Map<String,dynamic>? sub,checkout; bool loading=true,busy=false; String? message;
 @override void initState(){super.initState();_load();}
 Future<Map<String,dynamic>> call(String method,String route,{Map<String,dynamic>? body})async{
  final session=Supabase.instance.client.auth.currentSession,org=widget.organizationId?.trim();
  if(session==null)throw const _E('SIGN_IN_REQUIRED'); if(org==null||org.isEmpty)throw const _E('ORGANIZATION_REQUIRED');
  final r=http.Request(method,Uri.parse(PandoraConfig.ownerApiBaseUrl+route));
  r.headers.addAll({'Accept':'application/json','Authorization':'Bearer '+session.accessToken,'X-Organization-Id':org,if(body!=null)'Content-Type':'application/json'});
  if(body!=null)r.body=jsonEncode(body); final c=http.Client();
  try{final x=await c.send(r).timeout(const Duration(seconds:25));final raw=await x.stream.bytesToString();final v=raw.trim().isEmpty?<String,dynamic>{}:jsonDecode(raw);final p=v is Map?v.map((k,z)=>MapEntry(k.toString(),z)):<String,dynamic>{};if(x.statusCode<200||x.statusCode>=300)throw _E(p['code']?.toString()??'HTTP_'+x.statusCode.toString(),p['plainMessage']?.toString());return p;}finally{c.close();}
 }
 Future<Map<String,dynamic>> mutate(String route,Map<String,dynamic> body)async{
  try{return await call('POST',route,body:body);}on _E e{
   if(e.code!='AAL2_REQUIRED'&&e.code!='STEP_UP_REQUIRED')rethrow;final a=PandoraDependencies.of(context).auth;if(a is! ExtraIdentityVerificationSource)rethrow;
   final fs=await a.verifiedExtraIdentityFactors();if(!mounted||fs.isEmpty)rethrow;final i=await mfa(fs);if(i==null)rethrow;await a.verifyExtraIdentity(factorId:i.$1,code:i.$2);return call('POST',route,body:body);
  }
 }
 Future<(String,String)?> mfa(List<ExtraIdentityFactor> fs)async{
  final c=TextEditingController();var f=fs.first;final r=await showDialog<(String,String)>(context:context,builder:(x)=>AlertDialog(title:const Text('Verify identity'),content:Column(mainAxisSize:MainAxisSize.min,children:[
   const Text('Billing changes require your verified authenticator.'),DropdownButtonFormField<ExtraIdentityFactor>(initialValue:f,items:[for(final q in fs)DropdownMenuItem(value:q,child:Text(q.label))],onChanged:(q){if(q!=null)f=q;}),TextField(controller:c,keyboardType:TextInputType.number,maxLength:8,decoration:const InputDecoration(labelText:'Verification code',counterText:''))]),
   actions:[TextButton(onPressed:()=>Navigator.pop(x),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,(f.id,c.text.trim())),child:const Text('Verify'))]));
  c.dispose();return r;
 }
 String key(String p)=>p+'-'+DateTime.now().microsecondsSinceEpoch.toString()+'-'+math.Random.secure().nextInt(1<<30).toString();
 Future<void> _load()async{if(!mounted)return;setState(()=>loading=true);try{final p=await call('GET','/billing/paypal/status');if(mounted){setState((){sub=_map(p['subscription']);checkout=_map(p['checkout']);loading=false;});}}catch(e){if(mounted){setState((){loading=false;message=err(e);});}}}
 Future<void> run(Future<void> Function() f)async{if(busy)return;setState(()=>busy=true);try{await f();await _load();}catch(e){if(mounted)setState(()=>message=err(e));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> start(String code)async{await run(()async{final p=await mutate('/billing/paypal/checkout',{'planCode':code,'idempotencyKey':key('checkout-'+code),'returnUrl':'https://pandoras-box-system.vercel.app/','cancelUrl':'https://pandoras-box-system.vercel.app/'});await open(p['approvalUrl']);});}
 Future<void> change(String code)async{await run(()async{final p=await mutate('/billing/paypal/change-plan',{'planCode':code,'idempotencyKey':key('change-'+code)});if(p['approvalUrl']!=null)await open(p['approvalUrl']);});}
 Future<void> cancel()async{final ok=await showDialog<bool>(context:context,builder:(x)=>AlertDialog(title:const Text('Cancel subscription?'),content:const Text('Pandora will send the cancellation request to PayPal.'),actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Keep subscription')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Cancel subscription'))]));if(ok==true)await run(()async{await mutate('/billing/paypal/cancel',{'reason':'Cancelled by Pandora owner'});});}
 Future<void> reconcile()=>run(()async{await mutate('/billing/paypal/reconcile',const {});});
 Future<void> open(Object? v)async{final u=Uri.tryParse(v?.toString()??'');if(u==null||u.scheme!='https'||!await launchUrl(u,mode:LaunchMode.externalApplication))throw const _E('APPROVAL_URL_INVALID');}
 String err(Object e){if(e is! _E)return 'Pandora could not complete the billing request.';return switch(e.code){'SIGN_IN_REQUIRED'=>'Sign in again to manage billing.','ORGANIZATION_REQUIRED'=>'The PLP organization could not be verified.','AAL2_REQUIRED'||'STEP_UP_REQUIRED'=>'Verify your identity before changing billing.','PAYPAL_AUTH_FAILED'=>'PayPal is configured but its live credentials need attention.','PAYPAL_NOT_CONFIGURED'=>'PayPal credentials are not configured yet.','ACTIVE_SUBSCRIPTION_EXISTS'=>'An active subscription already exists for this workspace.','SUBSCRIPTION_NOT_FOUND'=>'No active Pandora subscription was found.','PAYPAL_PLAN_SAME'=>'That is already the active plan.',_=>e.message??'Pandora could not complete the billing request.'};}
 @override Widget build(BuildContext context){final state=sub?['state']?.toString().toLowerCase();final current=sub?['plan_code']?.toString()??checkout?['plan_code']?.toString()??'';final has=sub!=null&&state!=null&&state!='cancelled';return Scaffold(backgroundColor:canvas,body:SafeArea(child:RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(20,18,20,120),children:[
  Row(children:[IconButton(onPressed:onOpenNavigation,icon:const Icon(Icons.menu_rounded,color:ink)),const Expanded(child:Text('BILLING',style:TextStyle(color:ink,fontFamily:'serif',fontSize:16,fontWeight:FontWeight.w400,letterSpacing:2.6))),IconButton(onPressed:busy?null:_load,icon:const Icon(Icons.refresh_rounded,color:ink))]),
  const SizedBox(height:24),Text('Pandora subscription',style:Theme.of(context).textTheme.headlineSmall?.copyWith(color:ink,fontWeight:FontWeight.w700)),const SizedBox(height:8),const Text('Manage your Pandora plan without leaving the PLP workspace.',style:TextStyle(color:muted,height:1.45)),const SizedBox(height:20),
  Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFFF0ECE4),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE0D8CC))),child:Row(children:[const Icon(Icons.credit_card_rounded,color:accent,size:26),const SizedBox(width:14),Expanded(child:Text(state=='active'?'Active':state=='past_due'?'Payment needs attention':state=='suspended'?'Suspended':'No active subscription',style:const TextStyle(color:ink,fontSize:17,fontWeight:FontWeight.w700))),IconButton(onPressed:busy?null:reconcile,icon:const Icon(Icons.sync_rounded,color:ink))])),
  if(message!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(message!,style:const TextStyle(color:muted))),
  const SizedBox(height:22),if(loading)const Center(child:CircularProgressIndicator())else ...[
   const Text('Plans',style:TextStyle(color:ink,fontSize:20,fontWeight:FontWeight.w700)),const SizedBox(height:12),
   for(final p in plans)...[Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:current==p.$1?accent:const Color(0xFFE4DED4),width:current==p.$1?1.5:1)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text(p.$2,style:const TextStyle(color:ink,fontSize:20,fontWeight:FontWeight.w700))),if(current==p.$1)const Text('CURRENT',style:TextStyle(color:accent,fontSize:10,fontWeight:FontWeight.w800))]),const SizedBox(height:6),Text('$'+p.$3.toString()+' / month',style:const TextStyle(color:ink,fontSize:28,fontWeight:FontWeight.w800)),Text(p.$4,style:const TextStyle(color:muted)),const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy||current==p.$1?null:()=>has?change(p.$1):start(p.$1),child:Text(has?'Change to '+p.$2:'Start '+p.$2)))]) ),const SizedBox(height:12)],
   if(has)Row(children:[Expanded(child:OutlinedButton.icon(onPressed:busy?null:reconcile,icon:const Icon(Icons.sync_rounded),label:const Text('Reconcile'))),const SizedBox(width:10),Expanded(child:OutlinedButton.icon(onPressed:busy?null:cancel,icon:const Icon(Icons.close_rounded),label:const Text('Cancel')))])
  ]
 ]))));}
}
class _E implements Exception{const _E(this.code,[this.message]);final String code;final String? message;}
Map<String,dynamic> _map(Object? v)=>v is Map<String,dynamic>?v:v is Map?v.map((k,x)=>MapEntry(k.toString(),x)):<String,dynamic>{};
