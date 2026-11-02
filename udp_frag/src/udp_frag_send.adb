--  udp_frag_send <dest_host> <dest_port> <file>
--                [-c count] [-i interval_ms] [-s src_port] [-m mtu]
--                [-b sndbuf_bytes]
--
--  Sends the entire contents of <file> as the payload of one UDP datagram
--  (up to 65507 bytes), <count> times.  Anything larger than the path MTU
--  is fragmented by the local IP stack.  Prints the length, CRC-32, the
--  UDP checksum that must appear on the wire, and the predicted fragment
--  layout, for comparison with the receiver's report and a wire capture.

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Streams;      use Ada.Streams;
with Interfaces;       use Interfaces;
with GNAT.Sockets;     use GNAT.Sockets;
with UDP_Frag_Util;    use UDP_Frag_Util;
with UDP_Frag_Buffers; use UDP_Frag_Buffers;

procedure UDP_Frag_Send is

   procedure Usage is
   begin
      Put_Line (Standard_Error,
        "usage: udp_frag_send <dest_host> <dest_port> <file>"
        & " [-c count] [-i interval_ms] [-s src_port] [-m mtu]"
        & " [-b sndbuf_bytes]");
      Set_Exit_Status (2);
   end Usage;

   Count    : Positive := 1;
   Interval : Natural  := 100;           --  ms between datagrams
   Src_Port : Port_Type := Any_Port;
   MTU      : Positive := 1500;          --  for the printed prediction only
   Snd_Buf  : Natural  := 256 * 1024;

   Sock     : Socket_Type;
   Dest     : Sock_Addr_Type (Family_Inet);
   Local    : Sock_Addr_Type;
   Last     : Stream_Element_Offset;
   Sent     : Stream_Element_Offset;
   Csum     : Unsigned_16;
   Errors   : Natural := 0;
   A        : Positive := 4;

begin
   if Argument_Count < 3 then
      Usage;
      return;
   end if;

   while A <= Argument_Count loop
      if A = Argument_Count then
         Usage;
         return;
      end if;
      declare
         Opt : constant String := Argument (A);
         Val : constant String := Argument (A + 1);
      begin
         if    Opt = "-c" then Count    := Positive'Value (Val);
         elsif Opt = "-i" then Interval := Natural'Value (Val);
         elsif Opt = "-s" then Src_Port := Port_Type'Value (Val);
         elsif Opt = "-m" then MTU      := Positive'Value (Val);
         elsif Opt = "-b" then Snd_Buf  := Natural'Value (Val);
         else
            Usage;
            return;
         end if;
      end;
      A := A + 2;
   end loop;

   Load_File (Argument (3), Data_Buf, Last);

   Dest.Addr := Resolve (Argument (1));
   Dest.Port := Port_Type'Value (Argument (2));

   Create_Socket (Sock, Family_Inet, Socket_Datagram);
   Set_Socket_Option (Sock, Socket_Level, (Send_Buffer, Snd_Buf));
   if Src_Port /= Any_Port then
      Bind_Socket (Sock, (Family_Inet, Any_Inet_Addr, Src_Port));
   end if;

   --  connect() pins the route, so getsockname() yields the actual source
   --  address and port the stack will put in the IP/UDP headers.
   Connect_Socket (Sock, Dest);
   Local := Get_Socket_Name (Sock);

   Csum := UDP_Checksum (To_Bytes (Local.Addr), To_Bytes (Dest.Addr),
                         Local.Port, Dest.Port, Data_Buf (1 .. Last));

   Put_Line ("udp_frag_send");
   Put_Line ("  file          : " & Argument (3));
   Put_Line ("  src           : " & Image (Local));
   Put_Line ("  dst           : " & Image (Dest));
   Put_Line ("  payload bytes :" & Last'Image
             & "   (UDP length" & Stream_Element_Offset'Image (Last + 8)
             & ", IP total" & Stream_Element_Offset'Image (Last + 28) & ")");
   Put_Line ("  payload CRC32 : " & Hex (CRC_32 (Data_Buf (1 .. Last))));
   Put_Line ("  UDP checksum  : " & Hex (Unsigned_32 (Csum), 4)
             & "   (must match wire and receiver)");
   Print_Fragment_Plan (Last, MTU);

   for I in 1 .. Count loop
      begin
         Send_Socket (Sock, Data_Buf (1 .. Last), Sent);
         if Sent /= Last then
            Errors := Errors + 1;
            Put_Line ("  send" & I'Image & ": SHORT,"
                      & Sent'Image & " of" & Last'Image);
         end if;
      exception
         when E : Socket_Error =>
            Errors := Errors + 1;
            Put_Line ("  send" & I'Image & ": "
                      & Error_Type'Image (Resolve_Exception (E)));
      end;
      if I < Count and then Interval > 0 then
         delay Duration (Interval) / 1000.0;
      end if;
   end loop;

   Put_Line ("  sent" & Natural'Image (Count - Errors) & " of" & Count'Image
             & " datagrams");
   Close_Socket (Sock);
   if Errors > 0 then
      Set_Exit_Status (1);
   end if;
end UDP_Frag_Send;
