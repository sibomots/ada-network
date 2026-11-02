--  Shared helpers for the UDP fragmentation test pair.
--  IPv4 only.  Portable GNAT.Sockets; no OS-specific bindings, so it builds
--  for VxWorks (RTP or DKM) as well as Linux/Windows hosts.

with Ada.Streams;  use Ada.Streams;
with Interfaces;   use Interfaces;
with GNAT.Sockets; use GNAT.Sockets;

package UDP_Frag_Util is

   --  65535 - 20 (minimum IPv4 header) - 8 (UDP header)
   Max_UDP_Payload : constant := 65_507;

   subtype Payload_Buffer is Stream_Element_Array (1 .. Max_UDP_Payload);
   subtype IPv4_Bytes     is Stream_Element_Array (1 .. 4);

   function To_Bytes (A : Inet_Addr_Type) return IPv4_Bytes;

   --  RFC 1071 one's-complement sum, folded to 16 bits, not complemented.
   --  Initial allows chaining; Data is assumed to start on an even offset
   --  of the overall sum (true for pseudo-header -> UDP header -> payload).
   function Ones_Sum
     (Data    : Stream_Element_Array;
      Initial : Unsigned_32 := 0) return Unsigned_32;

   --  The UDP checksum (RFC 768) that must appear in the UDP header on the
   --  wire for this datagram: pseudo-header + UDP header (checksum field 0)
   --  + payload, complemented; a computed 0 is transmitted as 16#FFFF#.
   function UDP_Checksum
     (Src, Dst           : IPv4_Bytes;
      Src_Port, Dst_Port : Port_Type;
      Payload            : Stream_Element_Array) return Unsigned_16;

   --  CRC-32 (IEEE 802.3, reflected, init/xorout 16#FFFFFFFF#).
   function CRC_32 (Data : Stream_Element_Array) return Unsigned_32;

   --  Fragment-data bytes per IPv4 fragment at MTU (20-byte IP header,
   --  no options), rounded down to the 8-byte fragment-offset unit.
   function Frag_Data_Bytes (MTU : Positive) return Positive;

   --  Fragment count for a datagram with this UDP payload length.
   function Expected_Fragments
     (Payload_Len : Stream_Element_Offset; MTU : Positive) return Positive;

   --  0-based fragment index carrying 0-based UDP payload byte Offset.
   function Fragment_Of
     (Offset : Stream_Element_Offset; MTU : Positive) return Natural;

   function Hex (V : Unsigned_32; Digits_N : Positive := 8) return String;

   --  Read a whole file into Buf (1 .. Last).  Raises Constraint_Error if
   --  the file does not fit in Buf.
   procedure Load_File
     (Name : String;
      Buf  : out Stream_Element_Array;
      Last : out Stream_Element_Offset);

   --  Print the predicted on-wire fragment layout.
   procedure Print_Fragment_Plan
     (Payload_Len : Stream_Element_Offset; MTU : Positive);

   --  Resolve dotted-quad or host name to an IPv4 address.
   function Resolve (Host : String) return Inet_Addr_Type;

end UDP_Frag_Util;
