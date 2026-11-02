--  Large buffers live at library level, not on the main task's stack:
--  VxWorks RTP / task stacks are commonly far smaller than 64 KiB.

with UDP_Frag_Util; use UDP_Frag_Util;

package UDP_Frag_Buffers is
   Data_Buf : Payload_Buffer;   --  payload to send / payload received
   Ref_Buf  : Payload_Buffer;   --  receiver's reference copy of the file
end UDP_Frag_Buffers;
