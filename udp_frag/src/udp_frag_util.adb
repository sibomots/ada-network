with Ada.Text_IO;
with Ada.Streams.Stream_IO;

package body UDP_Frag_Util is

   --------------
   -- To_Bytes --
   --------------

   function To_Bytes (A : Inet_Addr_Type) return IPv4_Bytes is
      R : IPv4_Bytes;
   begin
      if A.Family /= Family_Inet then
         raise Constraint_Error with "IPv4 address required";
      end if;
      for I in 1 .. 4 loop
         R (Stream_Element_Offset (I)) := Stream_Element (A.Sin_V4 (I));
      end loop;
      return R;
   end To_Bytes;

   --------------
   -- Ones_Sum --
   --------------

   function Ones_Sum
     (Data    : Stream_Element_Array;
      Initial : Unsigned_32 := 0) return Unsigned_32
   is
      S : Unsigned_32 := Initial;
      I : Stream_Element_Offset := Data'First;
   begin
      while I < Data'Last loop
         S := S + Shift_Left (Unsigned_32 (Data (I)), 8)
                + Unsigned_32 (Data (I + 1));
         S := (S and 16#FFFF#) + Shift_Right (S, 16);
         I := I + 2;
      end loop;
      if I = Data'Last then              --  odd trailing byte, zero-padded
         S := S + Shift_Left (Unsigned_32 (Data (I)), 8);
      end if;
      while S > 16#FFFF# loop
         S := (S and 16#FFFF#) + Shift_Right (S, 16);
      end loop;
      return S;
   end Ones_Sum;

   ------------------
   -- UDP_Checksum --
   ------------------

   function UDP_Checksum
     (Src, Dst           : IPv4_Bytes;
      Src_Port, Dst_Port : Port_Type;
      Payload            : Stream_Element_Array) return Unsigned_16
   is
      UDP_Len : constant Unsigned_32 := 8 + Unsigned_32 (Payload'Length);

      function B (V : Unsigned_32; Shift : Natural) return Stream_Element is
        (Stream_Element (Shift_Right (V, Shift) and 16#FF#));

      SP : constant Unsigned_32 := Unsigned_32 (Src_Port);
      DP : constant Unsigned_32 := Unsigned_32 (Dst_Port);

      --  Pseudo-header (12) followed by UDP header with checksum = 0 (8)
      Hdr : constant Stream_Element_Array (1 .. 20) :=
        (Src (1), Src (2), Src (3), Src (4),
         Dst (1), Dst (2), Dst (3), Dst (4),
         0, 17, B (UDP_Len, 8), B (UDP_Len, 0),
         B (SP, 8), B (SP, 0), B (DP, 8), B (DP, 0),
         B (UDP_Len, 8), B (UDP_Len, 0), 0, 0);

      S : constant Unsigned_32 := Ones_Sum (Payload, Ones_Sum (Hdr));
      C : constant Unsigned_16 := not Unsigned_16 (S);
   begin
      return (if C = 0 then 16#FFFF# else C);
   end UDP_Checksum;

   ------------
   -- CRC_32 --
   ------------

   function CRC_32 (Data : Stream_Element_Array) return Unsigned_32 is
      C : Unsigned_32 := 16#FFFF_FFFF#;
   begin
      for E of Data loop
         C := C xor Unsigned_32 (E);
         for K in 1 .. 8 loop
            if (C and 1) /= 0 then
               C := Shift_Right (C, 1) xor 16#EDB8_8320#;
            else
               C := Shift_Right (C, 1);
            end if;
         end loop;
      end loop;
      return not C;
   end CRC_32;

   ---------------------
   -- Frag_Data_Bytes --
   ---------------------

   function Frag_Data_Bytes (MTU : Positive) return Positive is
     (((MTU - 20) / 8) * 8);

   ------------------------
   -- Expected_Fragments --
   ------------------------

   function Expected_Fragments
     (Payload_Len : Stream_Element_Offset; MTU : Positive) return Positive
   is
      IP_Payload : constant Natural := 8 + Natural (Payload_Len);
      F          : constant Positive := Frag_Data_Bytes (MTU);
   begin
      if IP_Payload + 20 <= MTU then
         return 1;
      end if;
      return (IP_Payload + F - 1) / F;
   end Expected_Fragments;

   -----------------
   -- Fragment_Of --
   -----------------

   function Fragment_Of
     (Offset : Stream_Element_Offset; MTU : Positive) return Natural is
     ((8 + Natural (Offset)) / Frag_Data_Bytes (MTU));

   ---------
   -- Hex --
   ---------

   function Hex (V : Unsigned_32; Digits_N : Positive := 8) return String is
      Map : constant String := "0123456789ABCDEF";
      R   : String (1 .. Digits_N);
      X   : Unsigned_32 := V;
   begin
      for I in reverse R'Range loop
         R (I) := Map (Integer (X and 16#F#) + 1);
         X := Shift_Right (X, 4);
      end loop;
      return "0x" & R;
   end Hex;

   ---------------
   -- Load_File --
   ---------------

   procedure Load_File
     (Name : String;
      Buf  : out Stream_Element_Array;
      Last : out Stream_Element_Offset)
   is
      use Ada.Streams.Stream_IO;
      F    : File_Type;
      Size : Count;
   begin
      Open (F, In_File, Name);
      Size := Ada.Streams.Stream_IO.Size (F);
      if Size > Count (Buf'Length) then
         Close (F);
         raise Constraint_Error with
           Name & ": " & Count'Image (Size) & " bytes exceeds"
           & Stream_Element_Offset'Image (Buf'Length) & "-byte limit";
      end if;
      Read (F, Buf (Buf'First .. Buf'First + Stream_Element_Offset (Size) - 1),
            Last);
      Close (F);
      if Last - Buf'First + 1 /= Stream_Element_Offset (Size) then
         raise Ada.Streams.Stream_IO.End_Error with Name & ": short read";
      end if;
   end Load_File;

   -------------------------
   -- Print_Fragment_Plan --
   -------------------------

   procedure Print_Fragment_Plan
     (Payload_Len : Stream_Element_Offset; MTU : Positive)
   is
      use Ada.Text_IO;
      Total : constant Natural  := 8 + Natural (Payload_Len);  --  IP payload
      F     : constant Positive := Frag_Data_Bytes (MTU);
      N     : constant Positive := Expected_Fragments (Payload_Len, MTU);
      Last_Off : constant Natural := (N - 1) * F;
   begin
      Put ("  fragments     :" & N'Image & " predicted at MTU" & MTU'Image);
      if N = 1 then
         New_Line;
         return;
      end if;
      Put_Line ("  ->" & Natural'Image (N - 1) & " x ip_len"
                & Natural'Image (20 + F) & " (MF=1), last: frag_off"
                & Last_Off'Image & " ip_len"
                & Natural'Image (20 + Total - Last_Off) & " (MF=0)");
   end Print_Fragment_Plan;

   -------------
   -- Resolve --
   -------------

   function Resolve (Host : String) return Inet_Addr_Type is
   begin
      if Is_IPv4_Address (Host) then
         return Inet_Addr (Host);
      end if;
      return Addresses (Get_Host_By_Name (Host), 1);
   end Resolve;

end UDP_Frag_Util;
