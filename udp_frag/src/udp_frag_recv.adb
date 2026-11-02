--  udp_frag_recv <port> -f <reference_file>
--                [-a local_addr] [-n expected_count] [-t idle_timeout_s]
--                [-m mtu] [-b rcvbuf_bytes]
--
--  Receives UDP datagrams on <port> and checks each one against the same
--  file the sender used: length, byte-for-byte content, CRC-32.  For any
--  mismatch it reports the first differing byte and which IP fragment(s)
--  (predicted at <mtu>) the differences fall in.
--
--  The stack discards any fragment with a bad IP header checksum and any
--  reassembled datagram with a bad UDP checksum, so a datagram reaching
--  this program means both passed on this end; the UDP checksum printed
--  here is recomputed independently and should equal the sender's.
--  Datagrams that never arrive (lost fragment, reassembly timeout,
--  checksum drop) show up as "missing" against -n.
--
--  -a binds to a specific local address; it is also the destination
--  address used in the pseudo-header, so the checksum is only printed
--  when -a is given.

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Streams;      use Ada.Streams;
with Interfaces;       use Interfaces;
with GNAT.Sockets;     use GNAT.Sockets;
with UDP_Frag_Util;    use UDP_Frag_Util;
with UDP_Frag_Buffers; use UDP_Frag_Buffers;
with GNAT.Strings;     use GNAT.Strings;

procedure UDP_Frag_Recv is

   procedure Usage is
   begin
      Put_Line (Standard_Error,
        "usage: udp_frag_recv <port> -f <reference_file> [-a local_addr]"
        & " [-n expected_count] [-t idle_timeout_s] [-m mtu]"
        & " [-b rcvbuf_bytes]");
      Set_Exit_Status (2);
   end Usage;

   Ref_Name  : String_Access;
   Have_Addr : Boolean   := False;
   Local_IP  : Inet_Addr_Type := Any_Inet_Addr;
   Expected  : Natural   := 0;           --  0 = run until idle timeout
   Idle_Max  : Natural   := 10;          --  seconds of silence to stop
   MTU       : Positive  := 1500;
   Rcv_Buf   : Natural   := 1024 * 1024;
   Port      : Port_Type;

   Sock      : Socket_Type;
   From      : Sock_Addr_Type;
   Last      : Stream_Element_Offset;
   Ref_Last  : Stream_Element_Offset;
   Ref_CRC   : Unsigned_32;

   Received  : Natural := 0;
   Good      : Natural := 0;
   Bad_Len   : Natural := 0;
   Bad_Data  : Natural := 0;
   Idle      : Natural := 0;
   A         : Positive := 2;

   --  Compare Data_Buf (1 .. Last) with the reference; report mismatches.
   function Check (N : Positive) return Boolean is
      Len_OK     : constant Boolean := Last = Ref_Last;
      Cmp_Last   : constant Stream_Element_Offset :=
                     Stream_Element_Offset'Min (Last, Ref_Last);
      First_Diff : Stream_Element_Offset := 0;
      N_Diff     : Natural := 0;
      Frag_Count : constant Positive :=
                     Expected_Fragments (Stream_Element_Offset'Max
                                           (Last, Ref_Last), MTU);
      Bad_Frag   : array (0 .. Frag_Count - 1) of Boolean :=
                     (others => False);
      CRC        : constant Unsigned_32 := CRC_32 (Data_Buf (1 .. Last));
   begin
      for I in 1 .. Cmp_Last loop
         if Data_Buf (I) /= Ref_Buf (I) then
            if N_Diff = 0 then
               First_Diff := I;
            end if;
            N_Diff := N_Diff + 1;
            Bad_Frag (Fragment_Of (I - 1, MTU)) := True;
         end if;
      end loop;

      Put ("  #" & N'Image & " from " & Image (From)
           & "  len=" & Last'Image & "  crc=" & Hex (CRC));
      if Have_Addr then
         Put ("  udp_csum=" & Hex (Unsigned_32 (
              UDP_Checksum (To_Bytes (From.Addr), To_Bytes (Local_IP),
                            From.Port, Port, Data_Buf (1 .. Last))), 4));
      end if;

      if Len_OK and then N_Diff = 0 then
         Put_Line ("  OK");
         return True;
      end if;

      Put_Line ("  MISMATCH");
      if not Len_OK then
         Put_Line ("      length" & Last'Image & " /= reference"
                   & Ref_Last'Image);
      end if;
      if N_Diff > 0 then
         Put_Line ("      " & N_Diff'Image & " differing bytes, first at"
                   & " payload offset" & Stream_Element_Offset'Image
                     (First_Diff - 1)
                   & " (fragment #"
                   & Natural'Image (Fragment_Of (First_Diff - 1, MTU))
                   & ")");
         Put ("      fragments with differences:");
         for F in Bad_Frag'Range loop
            if Bad_Frag (F) then
               Put (F'Image);
            end if;
         end loop;
         New_Line;
      end if;
      if not Len_OK then
         Bad_Len := Bad_Len + 1;
      else
         Bad_Data := Bad_Data + 1;
      end if;
      return False;
   end Check;

begin
   if Argument_Count < 1 then
      Usage;
      return;
   end if;
   Port := Port_Type'Value (Argument (1));

   while A <= Argument_Count loop
      if A = Argument_Count then
         Usage;
         return;
      end if;
      declare
         Opt : constant String := Argument (A);
         Val : constant String := Argument (A + 1);
      begin
         if    Opt = "-f" then Ref_Name := new String'(Val);
         elsif Opt = "-a" then Local_IP := Resolve (Val); Have_Addr := True;
         elsif Opt = "-n" then Expected := Natural'Value (Val);
         elsif Opt = "-t" then Idle_Max := Natural'Value (Val);
         elsif Opt = "-m" then MTU      := Positive'Value (Val);
         elsif Opt = "-b" then Rcv_Buf  := Natural'Value (Val);
         else
            Usage;
            return;
         end if;
      end;
      A := A + 2;
   end loop;

   if Ref_Name = null then
      Usage;
      return;
   end if;

   Load_File (Ref_Name.all, Ref_Buf, Ref_Last);
   Ref_CRC := CRC_32 (Ref_Buf (1 .. Ref_Last));

   Create_Socket (Sock, Family_Inet, Socket_Datagram);
   Set_Socket_Option (Sock, Socket_Level, (Reuse_Address, True));
   Set_Socket_Option (Sock, Socket_Level, (Receive_Buffer, Rcv_Buf));
   Set_Socket_Option (Sock, Socket_Level, (Receive_Timeout, 1.0));
   Bind_Socket (Sock, (Family_Inet, Local_IP, Port));

   Put_Line ("udp_frag_recv");
   Put_Line ("  listening     : " & Image (Get_Socket_Name (Sock)));
   Put_Line ("  reference     : " & Ref_Name.all & "  " & Ref_Last'Image
             & " bytes  crc=" & Hex (Ref_CRC));
   Print_Fragment_Plan (Ref_Last, MTU);

   loop
      exit when Expected > 0 and then Received >= Expected;
      begin
         Receive_Socket (Sock, Data_Buf, Last, From);
         Idle     := 0;
         Received := Received + 1;
         if Check (Received) then
            Good := Good + 1;
         end if;
      exception
         when E : Socket_Error =>
            case Resolve_Exception (E) is
               when Resource_Temporarily_Unavailable
                  | Connection_Timed_Out =>
                  Idle := Idle + 1;
                  exit when Idle >= Idle_Max;
               when others =>
                  raise;
            end case;
      end;
   end loop;

   Put_Line ("summary");
   Put_Line ("  received      :" & Received'Image);
   Put_Line ("  good          :" & Good'Image);
   Put_Line ("  bad length    :" & Bad_Len'Image);
   Put_Line ("  bad content   :" & Bad_Data'Image);
   if Expected > 0 then
      Put_Line ("  missing       :"
                & Integer'Image (Integer'Max (0, Expected - Received))
                & "  (dropped: lost/timed-out fragment or checksum fail)");
   end if;

   Close_Socket (Sock);
   if Good /= Received or else (Expected > 0 and then Received < Expected)
   then
      Set_Exit_Status (1);
   end if;
end UDP_Frag_Recv;
